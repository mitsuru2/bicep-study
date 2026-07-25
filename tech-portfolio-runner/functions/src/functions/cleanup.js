const { app } = require('@azure/functions');
const { listManagedContainerGroups, deleteContainerGroup } = require('../lib/aciRunner');
const { deleteRunnerInstance } = require('../lib/runnerTable');

const HANG_TIMEOUT_MS = 45 * 60 * 1000; // 45分 (Running状態のままハングしたとみなす閾値)
const ABSOLUTE_TIMEOUT_MS = 3 * 60 * 60 * 1000; // 3時間 (状態を問わず強制削除する安全弁)
const CONCURRENT_WARNING_THRESHOLD = 5;

function getState(group) {
  return group.containers?.[0]?.instanceView?.currentState?.state || group.instanceView?.state || 'Unknown';
}

app.timer('cleanup', {
  schedule: '0 */5 * * * *',
  handler: async (myTimer, context) => {
    const groups = await listManagedContainerGroups();
    let deletedCount = 0;
    let forcedCount = 0;

    for (const group of groups) {
      const state = getState(group);
      const createdAtTag = group.tags?.created_at;
      const ageMs = createdAtTag ? Date.now() - new Date(createdAtTag).getTime() : 0;

      let shouldDelete = false;
      let forced = false;

      if (state === 'Terminated' || state === 'Failed') {
        shouldDelete = true;
      } else if (ageMs > ABSOLUTE_TIMEOUT_MS) {
        shouldDelete = true;
        forced = true;
      } else if (state === 'Running' && ageMs > HANG_TIMEOUT_MS) {
        shouldDelete = true;
        forced = true;
      }

      if (shouldDelete) {
        context.log(`Deleting container group ${group.name} (state=${state}, forced=${forced})`);
        await deleteContainerGroup(group.name);
        await deleteRunnerInstance(group.name);
        deletedCount++;
        if (forced) {
          forcedCount++;
          context.warn(`Force-deleted hung/expired container group: ${group.name}`);
        }
      }
    }

    const stillActive = groups.length - deletedCount;
    if (stillActive > CONCURRENT_WARNING_THRESHOLD) {
      context.warn(`Unusually high number of concurrent ACI runners: ${stillActive}`);
    }

    context.log(`Cleanup run complete. Deleted ${deletedCount} (forced ${forcedCount}), ${stillActive} still active.`);
  },
});
