Feature: Clicking the retry affordance opens a dialog and resubmits the variant

  Background:
    Given a user with an attached avatar
    And the retry affordance is visible to everyone

  Scenario: Clicking the opener reveals the error inside the shadow-DOM dialog
    Given the avatar's :thumb_proc variant is in failed state with error "boom from upstream"
    When I visit the avatar page for the :thumb_proc variant
    And I click the retry opener
    Then the failure dialog should be open
    And the failure dialog should contain "boom from upstream"

  Scenario: Submitting Retry destroys the failed record and re-enqueues
    Given the avatar's :thumb_proc variant is in failed state with error "boom"
    When I visit the avatar page for the :thumb_proc variant
    And I click the retry opener
    And I click "Retry processing"
    Then the frame should render the processing state
    And the page should not have navigated away
