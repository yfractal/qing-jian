# README

A project for remember words easily.

## setup

1. Copy environment template:
   - `cp .env.example .env`
2. Set `OPENROUTER_API_KEY` in `.env`.
3. (Optional) Change `OPENROUTER_MODEL` if you want a different model.

The OpenRouter clients (`OpenRouterWordMeaningClient` and `OpenRouterSimilarWordsClient`) read these env vars:
- `OPENROUTER_API_KEY` (required)
- `OPENROUTER_MODEL` (optional, defaults to `deepseek/deepseek-v4-pro`)

## scenarios
- Adding Word
- Remember Words
- Statistic