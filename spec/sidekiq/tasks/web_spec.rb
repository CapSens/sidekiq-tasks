require "spec_helper"

RSpec.describe "Sidekiq::Tasks::Web", type: :request do
  include Rack::Test::Methods

  def app
    @app ||= Sidekiq::Web.new
  end

  before do
    if Sidekiq::Tasks::Web::SIDEKIQ_GTE_8_0_0
      Sidekiq::Web.configure do |config|
        config.middlewares.clear
        config.use Rack::Session::Cookie, secrets: "fake_secret_key" * 10, same_site: true, max_age: 86_400
      end
    end
  end

  describe "GET /tasks" do
    it "returns a 403 error when the user is not authorized", :aggregate_failures do
      allow(Sidekiq::Tasks.config).to receive(:authorization).and_return(->(_env) { false })

      get "/tasks"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("Forbidden")
    end

    it "correctly renders the tasks page when no tasks are found", :aggregate_failures do
      expect(Sidekiq::Tasks.tasks).to(
        receive(:where)
          .with(name: nil, desc: nil)
          .and_return(build_task_set)
      )

      get "/tasks"

      expect(last_response.status).to eq(200)
    end

    it "escapes the filter parameter in the HTML output" do
      xss_payload = '"><svg onload=alert(1)>'

      expect(Sidekiq::Tasks.tasks).to(
        receive(:where)
          .with(name: xss_payload, desc: xss_payload)
          .and_return(build_task_set)
      )

      get "/tasks", {"filter" => xss_payload}

      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include(xss_payload)
      expect(last_response.body).to include("&quot;&gt;&lt;svg onload=alert(1)&gt;")
    end

    it "correctly renders the tasks page when tasks are found", :aggregate_failures do
      expect(Sidekiq::Tasks.tasks).to(
        receive(:where)
          .with(name: nil, desc: nil)
          .and_return(build_task_set(build_task(name: "foo:bar")))
      )

      get "/tasks"

      expect(last_response.status).to eq(200)
    end
  end

  describe "GET /tasks/:name" do
    it "returns a 403 error when the user is not authorized", :aggregate_failures do
      allow(Sidekiq::Tasks.config).to receive(:authorization).and_return(->(_env) { false })

      get "/tasks/foo-bar"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("Forbidden")
    end

    it "returns a 404 error when the task is not found", :aggregate_failures do
      expect(Sidekiq::Tasks.tasks).to(
        receive(:find_by!)
          .with(name: "foo")
          .and_raise(Sidekiq::Tasks::NotFoundError)
      )

      get "/tasks/foo"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("Task not found")
    end

    it "renders the task details page when the task is found", :aggregate_failures do
      expect(Sidekiq::Tasks.tasks).to(
        receive(:find_by!)
          .with(name: "foo:bar")
          .and_return(build_task(name: "foo:bar"))
      )

      get "/tasks/foo-bar"

      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /tasks/:name/enqueue" do
    before { stub_env("RAILS_ENV", "development") }

    it "returns a 403 error when the user is not authorized", :aggregate_failures do
      allow(Sidekiq::Tasks.config).to receive(:authorization).and_return(->(_env) { false })

      post "/tasks/foo-bar/enqueue", {"env_confirmation" => "development"}

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("Forbidden")
    end

    it "enqueues the task with permitted params and redirects to the task", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])
      expect(Sidekiq::Tasks.tasks).to receive(:find_by!).twice.and_return(task) # twice because of redirect
      expect(task).to receive(:enqueue).with({"bar" => "baz"}, user: nil, dry_run: false)

      post "/tasks/foo-bar/enqueue", {"name" => "foo", "args" => {"bar" => "baz"}, "env_confirmation" => "development"}

      expect(last_response).to be_redirect
      follow_redirect!
      expect(last_request.path).to eq("/tasks/foo-bar")
    end

    it "enqueues the task in dry run mode when requested and supported", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])
      allow(task).to receive(:dry_run_supported?).and_return(true)
      expect(Sidekiq::Tasks.tasks).to receive(:find_by!).at_least(:once).and_return(task)
      expect(task).to receive(:enqueue).with({"bar" => "baz"}, user: nil, dry_run: true)

      post "/tasks/foo-bar/enqueue", {"args" => {"bar" => "baz"}, "dry_run" => "1", "env_confirmation" => "development"}

      expect(last_response).to be_redirect
    end

    it "ignores the dry run param when the task does not support it", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])
      allow(task).to receive(:dry_run_supported?).and_return(false)
      expect(Sidekiq::Tasks.tasks).to receive(:find_by!).at_least(:once).and_return(task)
      expect(task).to receive(:enqueue).with({"bar" => "baz"}, user: nil, dry_run: false)

      post "/tasks/foo-bar/enqueue", {"args" => {"bar" => "baz"}, "dry_run" => "1", "env_confirmation" => "development"}

      expect(last_response).to be_redirect
    end

    it "returns a 400 error when confirm param is invalid", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])
      expect(task).not_to receive(:enqueue)

      post "/tasks/foo-bar/enqueue", {"env_confirmation" => "an_invalid_confirm"}

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include("Invalid confirm")
    end

    it "redirects to /tasks when the task is not found", :aggregate_failures do
      expect(Sidekiq::Tasks.tasks).to(
        receive(:find_by!)
          .with(name: "foo:bar")
          .and_raise(Sidekiq::Tasks::NotFoundError)
      )

      post "/tasks/foo-bar/enqueue", {"env_confirmation" => "development"}

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("Task not found")
    end

    it "passes current_user when current_user is configured", :aggregate_failures do
      current_user_result = {"id" => 1, "email" => "admin@example.com"}
      allow(Sidekiq::Tasks.config).to receive(:current_user).and_return(->(_env) { current_user_result })

      task = build_task(name: "foo:bar", args: ["bar"])
      expect(Sidekiq::Tasks.tasks).to receive(:find_by!).at_least(:once).and_return(task)
      expect(task).to receive(:enqueue).with({"bar" => "baz"}, user: current_user_result, dry_run: false)

      post "/tasks/foo-bar/enqueue", {"name" => "foo", "args" => {"bar" => "baz"}, "env_confirmation" => "development"}

      expect(last_response).to be_redirect
    end

    it "passes current_user as nil when current_user is not configured", :aggregate_failures do
      allow(Sidekiq::Tasks.config).to receive(:current_user).and_return(nil)

      task = build_task(name: "foo:bar", args: ["bar"])
      expect(Sidekiq::Tasks.tasks).to receive(:find_by!).at_least(:once).and_return(task)
      expect(task).to receive(:enqueue).with({"bar" => "baz"}, user: nil, dry_run: false)

      post "/tasks/foo-bar/enqueue", {"name" => "foo", "args" => {"bar" => "baz"}, "env_confirmation" => "development"}

      expect(last_response).to be_redirect
    end

    it "returns a 400 error and does not enqueue the task when the params are invalid", :aggregate_failures do
      task = build_task(name: "foo:bar", args: ["bar"])
      expect(Sidekiq::Tasks.tasks).to receive(:find_by!).and_return(task)
      expect(task).not_to receive(:enqueue)

      post(
        "/tasks/foo-bar/enqueue",
        {
          "name" => "foo",
          "args" => {
            "bar" => "baz",
            "an_invalid_param" => "qux",
            "another_invalid_param" => "qux",
          },
          "env_confirmation" => "development",
        }
      )

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include("Invalid parameters: an_invalid_param, another_invalid_param")
    end
  end
end
