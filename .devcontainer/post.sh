#!/bin/bash
# .devcontainer/postCreate.sh
sudo mkdir -p /home/node/.azure
sudo mkdir -p /home/node/.gemini
sudo mkdir -p /home/node/.cache/google-vscode-extension
sudo chown -R node:node /home/node/.azure
sudo chown -R node:node /home/node/.gemini
sudo chown -R node:node /home/node/.cache/google-vscode-extension
az account show
