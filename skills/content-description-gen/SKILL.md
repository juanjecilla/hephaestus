---
name: content-description-gen
description: Propose localised contentDescription text for the static images in an Android app (drawables, illustrations, logos), by looking at each image, and write the strings into the app's resources for a person to review. Use when images have no alt text, when adding a language, or when deciding which images are decorative. Not for user-uploaded or remote images: those need on-device description at runtime.
license: Apache-2.0
---

# content-description-gen

Static images are known at build time, so a vision model can describe them **once**, in review, instead of on every user's phone. Dynamic images (posters, uploads) cannot: those need a runtime answer, for example ML Kit GenAI Image Description on the device (English only, beta).

## Steps

1. **Find the images**: usages of `painterResource`, `Image(`, `Icon(`, `AsyncImage(` and their drawables (`rg "painterResource|Image\("`).
2. **Decide first, describe second.** For each: is it **decorative** (a flourish, or it repeats adjacent text) → `contentDescription = null`; **informative** → needs text; **functional** (it is the button) → describe the *action*, not the picture ("Search", not "magnifying glass").
3. **Look at the image** (open the file; vision) and write one short phrase, no "image of", in every supported language.
4. **Write to resources** (`strings.xml` per locale) with a stable key (`cd_<screen>_<what>`), and wire the call sites.
5. **Hand over a table** for human review: file · decision · text per language. Nothing ships unreviewed.

## Rules

- A description says what matters **here**, not everything visible. A logo next to the company name is decorative.
- Never describe people by guessed attributes (age, ethnicity, feelings) beyond what the context needs.
- A model can describe what is not there. Read every line against the image.
- Same text for the same image everywhere, unless the context changes what matters.
