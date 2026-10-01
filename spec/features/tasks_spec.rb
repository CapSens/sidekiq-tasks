require "spec_helper"

RSpec.describe "Tasks page", type: :feature do
  before do
    allow(Sidekiq::Tasks).to receive(:tasks).and_return(tasks)
  end

  let(:tasks) do
    build_task_set(
      build_task(name: "posts:create", desc: "Create post", args: ["title"]),
      build_task(name: "users:create", desc: "Create user", args: ["name"]),
      build_task(name: "users:destroy", desc: "Destroy users"),
      build_task(name: "reports:generate", desc: "Weekly analytics export")
    )
  end

  it(
    "does not display the live poll button",
    skip: !Sidekiq::Tasks::Web::SIDEKIQ_GTE_7_0_1 && "requires Sidekiq >= 7.0.1"
  ) do
    visit "/tasks"
    expect(page).not_to have_css(".live-poll-start", visible: :all)
  end

  it "displays the tasks list" do
    visit "/tasks"

    aggregate_failures do
      tasks.each do |task|
        expect(page).to have_content(task.name)
        expect(page).to have_content(task.desc)
      end
    end
  end

  it "shows an empty state message when no tasks exist" do
    allow(Sidekiq::Tasks).to receive(:tasks).and_return(build_task_set)
    visit "/tasks"

    aggregate_failures do
      expect(page).to have_content("No tasks found")
      tasks.each { |task| expect(page).not_to have_content(task.name) }
    end
  end

  it "has a button to view the task details" do
    visit "/tasks"
    click_on "users:create"

    expect(page).to have_current_path("/tasks/users-create")

    aggregate_failures do
      expect(page).not_to have_content("Filter")
      expect(page).to have_content("Run task")
    end
  end

  it "paginates when exceeding the given count" do
    visit "/tasks?count=2"

    aggregate_failures do
      expect(page).to have_content("posts:create")
      expect(page).to have_content("reports:generate")
      expect(page).not_to have_content("users:destroy")
      expect(page).to have_content("2 / 4")
      expect(page).to have_content("«")
      expect(page).to have_content("»")
    end

    click_on "»"
    expect(page).not_to have_current_path("/tasks?count=2")

    aggregate_failures do
      expect(page).to have_content("users:destroy")
      expect(page).to have_content("2 / 4")
      expect(page).to have_content("«")
      expect(page).to have_content("»")
    end
  end

  it "does not show pagination when there's only one page" do
    visit "/tasks?count=4"

    aggregate_failures do
      expect(page).not_to have_content("4 / 4")
      expect(page).not_to have_content("«")
      expect(page).not_to have_content("»")
    end
  end

  it "updates the collection count when changed" do
    stub_const("Sidekiq::Tasks::Web::Search::DEFAULT_COUNT", 2)

    visit "/tasks"

    aggregate_failures do
      expect(page).to have_content("2 / 4")
      expect(page).to have_content("posts:create")
      expect(page).to have_content("reports:generate")
      expect(page).not_to have_content("users:destroy")
    end

    select "4", from: "count"
    click_on "Filter"

    expect(page).to have_current_path("/tasks?sort=name&direction=asc&filter=&count=4")

    aggregate_failures do
      tasks.each { |task| expect(page).to have_content(task.name) }
    end
  end

  it "sorts tasks by name descending when clicking the name header" do
    visit "/tasks?count=2"

    aggregate_failures do
      expect(page).to have_content("posts:create")
      expect(page).to have_content("reports:generate")
      expect(page).not_to have_content("users:destroy")
    end

    click_on "Name"

    expect(page).to have_content("users:destroy")

    aggregate_failures do
      expect(page).to have_content("users:create")
      expect(page).not_to have_content("posts:create")
    end
  end

  it "filters the tasks list by description" do
    visit "/tasks"
    fill_in "filter", with: "analytics"
    click_on "Filter"

    expect(page).to have_current_path("/tasks?sort=name&direction=asc&filter=analytics&count=15")

    aggregate_failures do
      expect(page).to have_content("reports:generate")
      expect(page).not_to have_content("posts:create")
      expect(page).not_to have_content("users:create")
      expect(page).not_to have_content("users:destroy")
    end
  end

  it "lists broken tasks without crashing the page", :aggregate_failures do
    broken_task = build_task(name: "billing:broken", error: "'sidekiq_options' magic comment is not valid YAML")
    allow(Sidekiq::Tasks).to receive(:tasks).and_return(build_task_set(broken_task, *tasks))

    visit "/tasks"

    expect(page).to have_content("billing:broken")
    expect(page).not_to have_css(".st-status-badge")
  end

  it "filters the tasks list when a filter is provided, and shows all tasks when cleared" do
    visit "/tasks"
    fill_in "filter", with: "users"
    click_on "Filter"

    expect(page).to have_current_path("/tasks?sort=name&direction=asc&filter=users&count=15")

    aggregate_failures do
      expect(page).to have_content("users:create")
      expect(page).to have_content("users:destroy")
      expect(page).not_to have_content("posts:create")
    end

    fill_in "filter", with: ""
    click_on "Filter"
    expect(page).to have_current_path("/tasks?sort=name&direction=asc&filter=&count=15")

    aggregate_failures do
      tasks.each { |task| expect(page).to have_content(task.name) }
    end
  end
end
