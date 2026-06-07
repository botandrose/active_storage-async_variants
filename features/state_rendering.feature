Feature: image_tag with async: true emits the right markup per variant state

  Scenario: A processed variant emits a plain <img> -- no turbo-frame, no chrome
    Given a user with an attached avatar
    And the avatar's :thumb_proc variant is in processed state
    When I visit the avatar page for the :thumb_proc variant
    Then the page should NOT contain a turbo-frame

  Scenario: An unprocessed variant emits a turbo-frame in processing state
    Given a user with an attached avatar
    And the avatar's :thumb_proc variant is in processing state
    When I visit the avatar page for the :thumb_proc variant
    Then the page should contain a turbo-frame
    And the frame should render the processing state

  Scenario: A processing variant renders an indeterminate progress bar before any heartbeat
    Given a user with an attached avatar
    And the avatar's :thumb_proc variant is in processing state
    When I visit the avatar page for the :thumb_proc variant
    Then the page should contain a turbo-frame
    And the frame should render a progress bar
    And the progress bar should be indeterminate
    And the placeholder image should reserve layout

  Scenario: A processing variant with reported progress renders a determinate progress bar
    Given a user with an attached avatar
    And the avatar's :thumb_proc variant is in processing state
    And the avatar's :thumb_proc variant has reported 42% progress
    When I visit the avatar page for the :thumb_proc variant
    Then the page should contain a turbo-frame
    And the progress bar should show 42%

  Scenario: A failed variant renders the failed partial inside the frame
    Given a user with an attached avatar
    And the retry affordance is visible to everyone
    And the avatar's :thumb_proc variant is in failed state with error "boom"
    When I visit the avatar page for the :thumb_proc variant
    Then the page should contain a turbo-frame
    And the frame should render the failed state
