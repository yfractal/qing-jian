# Remember Word Feedback Interaction Design

## Goal

Improve the Remember Words page so a learner gets immediate, clear feedback after submitting an answer, sees the correct answer when wrong, and then intentionally moves to the next due word.

The experience should feel calm, focused, and easy to use on mobile and desktop.

## Current Context

The app is a Rails application with the Remember Words page at `RememberWordsController#index`, rendered by `app/views/remember_words/index.html.erb`.

Today, answer submission happens through `WordQuestionRecordsController#create`. The controller records whether the selected choice is correct, then immediately redirects to the root path with the answered word included in `recalled_word_ids`. That means the user never sees whether their answer was correct before the next word loads.

The new design keeps the existing Rails-first shape and adds a feedback step between "submit answer" and "next word".

## Recommended Approach

Use a two-step server-rendered flow:

1. User answers the current question and submits the form.
2. The answer is saved.
3. The app redirects back to the Remember Words page in a result state for the same question.
4. The page shows whether the answer was correct.
5. If the answer was wrong, the page shows the correct answer.
6. User clicks `Next word`.
7. The app redirects back to the Remember Words page with the current word included in `recalled_word_ids`, so the next due word appears.

This keeps the core behavior usable without JavaScript and matches the current Rails controller/view style.

## Interaction States

### Question State

The default page state shows a single quiz card:

- Page title: `Remember Words`
- Direction selector: `English -> Chinese` and `Chinese -> English`
- Secondary action: `Add new word`
- Prompt text:
  - English to Chinese: show the English word and ask for the Chinese meaning.
  - Chinese to English: show the Chinese meaning and ask for the English word.
- Four large answer choices.
- Primary button: `Check answer`.

The entire answer row should be clickable. The radio input may remain for accessibility and form behavior, but the visual target should be the full answer card.

### Feedback State: Correct

After a correct answer, the same card changes into a success state:

- Status panel: `Correct`
- Supporting copy: short and positive, for example `Nice. You chose the right meaning.`
- The selected choice is highlighted green.
- Primary button: `Next word`.

No additional explanation is needed for correct answers.

### Feedback State: Incorrect

After an incorrect answer, the same card changes into a correction state:

- Status panel: `Not quite`
- Supporting copy: `Review the right answer, then continue.`
- The selected wrong choice is highlighted red.
- The correct choice is highlighted green.
- Clear answer line: `Correct answer: <answer text>`.
- Primary button: `Next word`.

This state should avoid a harsh failure tone. The purpose is fast correction, not punishment.

### Completion State

When there are no due words, show a polished completion card instead of plain text:

- Title: `All caught up`
- Body: `You have recalled all words due today.`
- Secondary action: `Add new word`

If the user completed one pass but some words are still due because the recall schedule kept them active, keep the existing pass reset behavior and show the next pass normally.

## Visual Design

Use a clean, centered, mobile-first flashcard layout.

### Page

- Background: soft warm gray or pale blue-gray.
- Content width: about `720px`.
- Body spacing: generous top/bottom padding.
- Typography: keep the current system font stack.

### Header

Use a compact header above the card:

- Small eyebrow label: `Daily Review`
- Main heading: `Remember Words`
- Direction selector as segmented pills.
- `Add new word` as a secondary text or outline button.

### Quiz Card

The card should be the visual center:

- White background.
- Rounded corners, about `24px`.
- Soft shadow.
- Comfortable padding.
- Big question text, around `2.25rem` to `3rem` depending on screen width.
- Muted helper text below the question.

### Choices

Each choice should look like a tappable option:

- Full-width row.
- Rounded corners.
- Light border.
- Padding around `1rem`.
- Hover/focus state.
- Selected state: blue border and light blue background.
- Correct state: green border and green-tinted background.
- Incorrect selected state: red border and red-tinted background.

### Buttons

Primary actions should be visually clear:

- `Check answer` before submission.
- `Next word` after feedback.

Use a strong blue primary button with rounded corners and a full-width layout on small screens.

## Data Flow

### Submit Answer

`WordQuestionRecordsController#create` should:

1. Find the submitted `WordQuestion`.
2. Resolve the picked choice.
3. Create `WordQuestionRecord`.
4. Redirect to the Remember Words page in result mode.

The result redirect should include enough state to render the answered question and result:

- `direction`
- existing `recalled_word_ids`
- new `result_record_id`

The current word should not be added to `recalled_word_ids` until the learner clicks `Next word`.

### Render Result

`RememberWordsController#index` should detect `result_record_id` and render the answered question in feedback state.

It should derive:

- Whether the answer was correct.
- Which choice was selected.
- Which choice is correct.
- The display text for each choice based on direction.
- The `Next word` URL.

### Next Word

The `Next word` button/link should go to `root_path` with:

- `direction`
- existing `recalled_word_ids`
- the answered word id appended to `recalled_word_ids`

This loads the next due word using the existing filtering behavior.

## Error Handling

If an invalid or stale `result_record_id` is provided, the app should fall back to the normal question state instead of crashing.

If answer submission fails, keep the existing alert behavior and redirect back to the current question.

## Accessibility

- Keep native radio inputs or equivalent accessible form controls.
- Ensure each answer choice has a visible focus state.
- Use text labels, not color alone, to communicate correctness.
- The feedback panel should include explicit words like `Correct` or `Not quite`.
- Buttons and links should have clear names.

## Testing

Add or update controller tests for:

- Correct answer submission redirects to result mode.
- Incorrect answer submission redirects to result mode.
- Result mode shows the same question instead of immediately advancing.
- `Next word` URL includes the answered word id in `recalled_word_ids`.
- Invalid result state falls back safely.

Add or update view/system-level coverage if available for:

- Correct state shows `Correct`.
- Incorrect state shows `Correct answer`.
- Choice styling classes distinguish selected wrong and correct choices.

## Out of Scope

- Full JavaScript-only interactions.
- Progress charts or statistics.
- Changing the recall scheduling algorithm.
- Reworking the word-question association model beyond what existing active plans already cover.
