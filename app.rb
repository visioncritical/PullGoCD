# Accept POST webhooks from Github, convert JSON body to hash -DONE
# Send POST to send PR number to Go API as PULL_REQUEST env var -DONE
# Retry POST (sleep 15) if unsuccessful up to 5min - DONE
# Send POST to Slack if unsuccessful after 5min - DONE
# Send POST to set Github pull request status to pending - DONE
# Ignore PR's that are not mergeable - DONE
# Reject PR's to unauthorized branches, comments/closes PR - DONE
# Accept POST from Go conditional task and send POST update Github PR status and Slack - DONE
# Randomly choose Go Pipeline from comma seperated list to allow for parallel testing - DONE
require 'sinatra'
require 'sinatra/config_file'
require 'json'
require 'pry'
require 'rest-client'

set :bind, '0.0.0.0'
config_file 'config.yml'

before do
  @go_user = settings.go_user
  @go_pass = settings.go_pass
  @go_server = settings.go_server
  @go_api_url = "http://#{@go_user}:#{@go_pass}@#{@go_server}/go/api/pipelines/"
  @go_pipeline = settings.go_pipeline.split(',')
  @go_pipeline_baseurl = "http://#{@go_server}/go/tab/pipeline/history/"
  @github_token = settings.github_token
  @slack_url = settings.slack_url if defined?(settings.slack_url)
  @auth_branch = settings.authorized_branch if defined?(settings.authorized_branch)
  @git_headers = {
    Authorization: "token #{@github_token}",
    content_type: :json,
    accept: :json
  }
end

helpers do
  # Start PR CI tests
  def start_pull_test(pull_number,pull_status_url,pull_html_url,pull_title,pull_author,pull_repo_url,pull_comments_url,pull_url)
    go_post = "variables[pull_number]=#{pull_number}&\
variables[pull_status_url]=#{pull_status_url}&\
variables[pull_html_url]=#{pull_html_url}&\
variables[pull_comments_url]=#{pull_comments_url}&\
variables[pull_url]=#{pull_url}&\
variables[pull_title]=#{pull_title}&\
variables[pull_author]=#{pull_author}&\
variables[pull_repo_url]=#{pull_repo_url}"

    # Retry starting Pipeline for 5min
    tries ||= 20
    begin
      rand_pipeline = @go_pipeline.sample
      @go_pipeline_url = @go_pipeline_baseurl + rand_pipeline
      RestClient.post(
        @go_api_url + rand_pipeline + '/schedule',
        go_post,
        content_type: 'application/x-www-form-urlencoded'
      )
    rescue StandardError => e
      if (tries -= 1) > 0
        @go_pipeline.delete(rand_pipeline) if @go_pipeline.count > 1
        puts "#{Time.now} Retries left: #{tries} Exception: #{e.inspect}"
        sleep 15
        retry
      else
        # Notify Slack channel if PR Pipeline failed to start
        notify_slack(
          "Pull Request #{pull_number} Could Not Be Tested",
          pull_author,
          pull_html_url,
          "#{e.inspect}",
          'danger'
        )
        set_pr_status(
          pull_status_url,
          'error',
          @go_pipeline_url,
          'Pull Request testing could not be started.'
        )
      end
    end
  end

  # Send notification to Slack
  def notify_slack(message,author,msg_link='',body,color)
    slack_headers = {
      content_type: :json,
      accept: :json
    }
    attachment = [
      {
        author_name: author,
        fallback: message,
        title: message,
        title_link: msg_link,
        text: body,
        color: color
      }
    ]
    payload = {
      username: 'Chef CI',
      attachments: attachment
    }
    RestClient.post(
      @slack_url,
      payload.to_json,
      slack_headers
    ) if defined?(settings.slack_url)
  end

  # Set Github Pull Request status
  def set_pr_status(pull_status_url,state,target_url,description)
    url = pull_status_url
    payload = {
      state: state,
      target_url: target_url,
      description: description
    }
    RestClient.post(
      url,
      payload.to_json,
      @git_headers
    )
  end

  # Add a comment to PR
  def add_pr_comment(pull_comments_url,comment_body)
    url = pull_comments_url
    payload = {
      body: "#{comment_body}"
    }
    RestClient.post(
      url,
      payload.to_json,
      @git_headers
    )
  end

  # Reject PR on unauthorized branches
  def reject_unauth_pr(pull_comments_url,pull_url,pull_branch)
    return if pull_branch == @auth_branch
    # Add reason for rejection as comment on PR
    add_pr_comment(pull_comments_url,"Pull requests are only allowed on the #{@auth_branch} branch.")

    # Close PR
    url = pull_url
    payload = {state: 'closed'}
    RestClient.post(
      url,
      payload.to_json,
      @git_headers
    )
    halt 401, "Pull requests are only allowed on the #{@auth_branch} branch."
  end
end

post '/GitHubWebhook' do
  body = request.body.read
  data = JSON.parse(body)
  pull_number = data['pull_request']['number']
  pull_author = data['pull_request']['user']['login']
  pull_status_url = data['pull_request']['statuses_url']
  pull_html_url = data['pull_request']['html_url']
  pull_comments_url = data['pull_request']['comments_url']
  pull_url = data['pull_request']['url']
  pull_title = data['pull_request']['title']
  pull_repo_url = data['pull_request']['base']['repo']['clone_url']
  pull_branch = data['pull_request']['base']['ref']
  pull_mergeable = data['pull_request']['mergeable']

  # Do nothing if PR is not mergeable
  halt 200, 'PR is not mergeable.' if pull_mergeable.to_s == 'false'

  # Do nothing if PR is closed
  halt 200, "PR action \"#{data['action']}\" does not trigger pipelines." unless %w(opened synchronize reopened).include?(data['action'])

  # Reject PR on unauthorized branch if authorized branch setting is defined
  reject_unauth_pr(
    pull_comments_url,
    pull_url,
    pull_branch
  ) if defined?(settings.authorized_branch)

  # Kickoff Go Pipeline
  start_pull_test(
    pull_number,
    pull_status_url,
    pull_html_url,
    pull_title,
    pull_author,
    pull_repo_url,
    pull_comments_url,
    pull_url
  )

  # Set PR to pending
  set_pr_status(
    pull_status_url,
    'pending',
    @go_pipeline_url,
    'Pull Request submitted for CI testing'
  )
end

post '/GoWebhook' do
  body = request.body.read
  data = JSON.parse(body)
  pull_status_url = data['pull_status_url']
  pull_html_url = data['pull_html_url']
  pull_url = data['pull_url']
  pull_comments_url = data['pull_comments_url']
  pull_number = data['pull_number']
  pull_status = data['status']
  pull_author = data['pull_author']
  pull_title = data['pull_title']
  go_job_console_url = data['go_job_console_url']
  go_description = data['go_description']

  # Set PR status to success or failure from Go result
  set_pr_status(
    pull_status_url,
    pull_status,
    go_job_console_url,
    go_description
  )

  # Add comment to PR if failure to send notification to submitter
  add_pr_comment(
    pull_comments_url,
    "Your Pull Request #{pull_number} has failed automated testing. Please see #{go_job_console_url} for more information."
  ) if pull_status == 'failure'

  # Send Slack notification if GO PR test completed successfully
  notify_slack(
    "PR##{pull_number} by #{pull_author} passed validation and is ready for review.",
    pull_author,
    pull_html_url,
    pull_title,
    'good'
  ) if pull_status == 'success'
end
