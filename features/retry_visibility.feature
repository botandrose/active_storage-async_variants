Feature: The retry affordance is gated by ActiveStorage::AsyncVariants.retry_visible_if

  Scenario: When retry_visible_if returns true, the retry chrome renders
    Given a user with an attached avatar
    And the retry affordance is visible to everyone
    And the avatar's :thumb_proc variant is in failed state with error "boom"
    When I visit the avatar page for the :thumb_proc variant
    Then the retry affordance should be visible

  Scenario: When retry_visible_if returns false, the retry chrome is omitted
    Given a user with an attached avatar
    And the retry affordance is hidden
    And the avatar's :thumb_proc variant is in failed state with error "boom"
    When I visit the avatar page for the :thumb_proc variant
    Then the retry affordance should NOT be visible

  Scenario: A proc that consults current_user gates the affordance per-viewer
    Given a user with an attached avatar
    And the retry affordance requires a signed-in user
    And the avatar's :thumb_proc variant is in failed state with error "boom"
    When I sign in as the user
    And I visit the avatar page for the :thumb_proc variant
    Then the retry affordance should be visible
