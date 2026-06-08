# frozen_string_literal: true

Given /^a user with an attached avatar$/ do
  @user = User.create!
  attach_avatar_to(@user)
end

Given /^the avatar's :(\w+) variant is in (pending|processing|processed|failed) state(?: with error "([^"]+)")?$/ do |variant_name, state, error|
  variant = @user.avatar.variant(variant_name.to_sym)
  if state == "processed"
    simulate_processed_variant(variant)
  else
    create_variant_record(variant, state: state, error: error)
  end
end

Given /^the avatar's :(\w+) variant has reported (\d+)% progress$/ do |variant_name, percent|
  variant = @user.avatar.variant(variant_name.to_sym)
  record = variant.blob.variant_records.find_by(variation_digest: variant.variation.digest)
  record.update!(progress: percent.to_i)
end

Then /^the frame should render a progress bar$/ do
  expect(page).to have_css("turbo-frame progress-bar", visible: :all)
end

Then /^the frame should render an error progress bar$/ do
  expect(page).to have_css("turbo-frame progress-bar[error]", visible: :all)
end

Then /^the progress bar should be indeterminate$/ do
  expect(page).to have_css("turbo-frame progress-bar:not([percent])", visible: :all)
end

Then /^the progress bar should show (\d+)%$/ do |percent|
  expect(page).to have_css(%(turbo-frame progress-bar[percent="#{percent}"]), visible: :all)
end

# Default (visible-only) matcher: passes only because the placeholder is hidden
# via opacity (not visibility/display), so Capybara still sees it.
Then /^the placeholder image should reserve layout$/ do
  expect(page).to have_css("turbo-frame .async-variant-processing img")
end

Given /^the retry affordance is visible to everyone$/ do
  ActiveStorage::AsyncVariants.retry_visible_if { true }
end

Given /^the retry affordance is hidden$/ do
  ActiveStorage::AsyncVariants.retry_visible_if { false }
end

Given /^the retry affordance requires a signed-in user$/ do
  ActiveStorage::AsyncVariants.retry_visible_if { current_user.present? }
end

When /^I sign in as the (admin|user)$/ do |_kind|
  visit "/session/#{@user.id}"
end

When /^I visit the avatar page for the :(\w+) variant$/ do |variant_name|
  visit "/avatars/#{@user.id}/#{variant_name}"
end

Then /^the page should contain a turbo-frame$/ do
  expect(page).to have_css("turbo-frame")
end

Then /^the page should NOT contain a turbo-frame$/ do
  expect(page).to have_no_css("turbo-frame")
  expect(page).to have_css("img")
end

Then /^the frame should render the (failed|processing|processed) state$/ do |state|
  expect(page).to have_css("turbo-frame .async-variant-#{state}")
end

Then /^the retry affordance should be visible$/ do
  expect(page).to have_css("async-variant-retry", visible: :all)
end

Then /^the retry affordance should NOT be visible$/ do
  expect(page).to have_no_css("async-variant-retry", visible: :all)
end

Then /^the page should not have navigated away$/ do
  expect(page).to have_css("h1#page-marker")
end

Then /^the failure dialog should be open$/ do
  expect(page).to have_css("async-variant-retry", visible: :all)
  open = page.evaluate_script(<<~JS)
    (() => {
      const host = document.querySelector("async-variant-retry")
      if (!host || !host.shadowRoot) return false
      const dialog = host.shadowRoot.querySelector("dialog")
      return dialog ? dialog.open : false
    })()
  JS
  expect(open).to eq(true)
end

Then /^the failure dialog should contain "([^"]+)"$/ do |text|
  contains = page.evaluate_script(<<~JS)
    (() => {
      const host = document.querySelector("async-variant-retry")
      if (!host || !host.shadowRoot) return false
      return host.shadowRoot.textContent.includes(#{text.inspect})
    })()
  JS
  expect(contains).to eq(true)
end

# Wait for Turbo to swap the frame and our shim to attach the shadow root.
def wait_for_shadow!
  Timeout.timeout(5) do
    loop do
      attached = page.evaluate_script("!!document.querySelector('async-variant-retry')?.shadowRoot")
      break if attached
      sleep 0.05
    end
  end
end

When /^I click the retry opener$/ do
  wait_for_shadow!
  page.evaluate_script(<<~JS)
    document.querySelector("async-variant-retry").shadowRoot.querySelector(".opener").click()
  JS
end

When /^I click "Retry processing"$/ do
  wait_for_shadow!
  page.evaluate_script(<<~JS)
    document.querySelector("async-variant-retry").shadowRoot.querySelector("footer button").click()
  JS
end

When /^I close the failure dialog$/ do
  wait_for_shadow!
  page.evaluate_script(<<~JS)
    document.querySelector("async-variant-retry").shadowRoot.querySelector("dialog > button[type=button]").click()
  JS
end
