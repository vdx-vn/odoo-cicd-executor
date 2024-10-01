# Execute CICD workflow for private Odoo repo

## Prerequisite

1. [Install Check Runs Manager GitHub App](https://github.com/apps/check-runs-manager)
1. [Generate an user access token for Check Runs Manager App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)

    we will use this token to create and update status for run check

1. [Install Packages Manager GitHub App](https://github.com/apps/packages-manager)
1. [Generate an user access token for Packages Manager GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)

    We will use this token to push and delete packages in the GitHub Container Registry.

## Setup

For a newly Odoo repository that needs a CICD process, follow the instructions below:

1. Determine the environment name  
  e.g:  

- repo name: *vdx-vn/cuu-long*
- branch: *dev*
- --> environment name: *vdx-vn/cuu-long/dev* *(1)*

1. Go to [repo settings](https://github.com/vdx-vn/odoo-cicd-executor/settings/environments) and create a new environment named *(1)* with the following secrets and variables:

   - *Environment secrets:*
     - **SERVER_DB_PASSWORD**: Server database password for the backup process
     - **SERVER_PRIVATE_KEY**: Server private key file for access to the server through SSH or SCP protocol
     - **TELEGRAM_CHANNEL_ID**: Telegram channel ID for notifications through the Telegram channel
     - **TELEGRAM_TOKEN**: Telegram BOT token (the BOT added to this TELEGRAM_CHANNEL_ID)

   - *Environment variables:*
     - **DB_IMAGE_TAG**: Postgres image tag name defined in the docker-compose.yml file of the private repo
     - **ODOO_IMAGE_TAG**: Odoo image tag name defined in the docker-compose.yml file of the private repo
     #fixme: update odoo_image_tag_test documentation here
     - **SERVER_DEPLOY_PATH**: Server deployment path, the folder containing the docker-compose.yml file
     - **SERVER_HOST**: Server IP address
     - **SERVER_ODOO_DB_NAME**: Odoo database name
     - **SERVER_ODOO_URL**: Odoo URL
     - **SERVER_SSH_PORT**: Server SSH port
     - **SERVER_USER**: Username for SSH connection

1. Continuing follow the instruction inside 'README.md' file of the repo *(1)*

## Reference

1. [GitHub REST API](https://octokit.github.io/rest.js)
1. [GitHub Script Action](https://github.com/actions/github-script)
