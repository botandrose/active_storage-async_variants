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

  Scenario: A failed variant renders the failed partial inside the frame
    Given a user with an attached avatar
    And the avatar's :thumb_proc variant is in failed state with error "boom"
    When I visit the avatar page for the :thumb_proc variant
    Then the page should contain a turbo-frame
    And the frame should render the failed state
