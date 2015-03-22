PullGoCD
==============

Webhook receiver to accept Github Pull Requests and send them to Go-CD and notify in Slack.

## Features
* Sets Github PR status to "pending" and triggers Go Pipeline specified in config.yml
* Retries trigger up to 5min and if unsuccessful, updates Github PR status and optionally notifies Slack channel
* Mutiple Go Pipelines can be specified to allow for parallelization 
* On success/failure of Go pipeline run, update PR status and optionally notify Slack on success (conditional tasks in Go required)
* Ignores Github PR's that are not of action `opened`, `reopened`, `sychronize`, or are unmergeable
* Optionally rejects Github PR's that are submitted to a specified unauthorized branch by closing PR

## Prerequisites
* Github or Github Enterprise needs to be able to reach this app, firewalls may need to be opened or use [ngrok](http://ngrok.com) (be sure to check with your company's security policies.)
* Set app URL in [repo webhooks settings](https://developer.github.com/webhooks/creating/) with trigger on "Pull Request" events.
* A [personal access token](https://help.github.com/articles/creating-an-access-token-for-command-line-use/) is required to update the PR status. It requires the `public_repo` and `repo:status` access.
* Slack notifications require an [Incoming Webhook](https://api.slack.com/incoming-webhooks)
* Go pipeline requires the following EMPTY environment variables:
 * `pull_number` - Pull request number
 * `pull_status_url` - Pull request statuses API endpoint
 * `pull_html_url` - Pull request URL
 * `pull_comments_url` - Pull comments URL
 * `pull_title` - Pull request title
 * `pull_author` - Pull request author
 * `pull_repo_url` - clone URL of repo that pull request is submitted against
 * `pull_url` - Pull API URL

* Go pipeline requires conditional tasks to post back to receiver on /GoWebhook with JSON body
Curl Example:
```
go_job_console_url=${GO_SERVER_URL}tab/build/detail/${GO_PIPELINE_NAME}/${GO_PIPELINE_COUNTER}/${GO_STAGE_NAME}/${GO_STAGE_COUNTER}/${GO_JOB_NAME}#tab-console
curl -XPOST http://pullgocd.example.local '
{
    "pull_number": "$pull_number",
    "pull_status_url": "$pull_status_url",
    "pull_html_url": "$pull_html_url",
    "pull_comments_url": "$pull_comments_url",
    "pull_url": "$pull_url",
    "pull_title": "$pull_title",
    "pull_author": "$pull_author",
    "status": "failure",
    "go_job_console_url": "$go_job_console_url",
    "go_description": "Tests failed, click on Details for more information."
}'
```

#### Configuration File (see [config.yml.example](config.yml.example) file):
* `go_user` - Go user (string)
* `go_pass` - Go user password (string)
* `go_server` - Go server hostname including port ie. `go.example.local:8080` (string)
* `go_pipeline` - list of Go Pipeline Names comma seperated  (string)
* `github_token` - Application token, requires access to Repo Status (string)
* `slack_url` - Slack webhook URL (optional string)
* `authorized_branch` - Branch where PR's are allowed to be submitted (optional string)

## Installation
* PullGoCD is a sinatra app which obviously requires ruby (tested with 1.9.3)
* Install gem requirements with `bundle install` if you have the bundler gem installed, otherwise manually install the required gems listed in [app.rb](app.rb)
* Run the following to start the get running:
```
git clone https://github.com/visioncritical/PullGoCD.git
ruby app.rb
```
This will start the app on the default sinatra port 4567
* You can also run this under [Phusion Passenger](https://www.phusionpassenger.com/) by following the Passenger installation instructions and pointing your config to `/pathto/PullGoCD/public`
