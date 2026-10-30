# Contributing to Tuckaway

**Everyone is welcome here.** First-timers, seasoned macOS developers, designers,
people who just want one bug gone: come on in.

## AI is welcome, all of it

Tuckaway is openly vibe coded, and **every use of AI is allowed**. Autocomplete,
chatting with a model, pair programming with an agent, or an agent writing the
entire pull request are all fine. You don't need to apologize for it or hide it.

If you want to mention which tools you used, that's welcome, but it's optional.
We judge changes on whether they work, not on how they were written.

## How to contribute

- **Report a bug or suggest an idea:**
  [open an issue](https://github.com/Bruno-Alumn/Tuckaway/issues/new). Include
  your macOS version and, if you can, a screenshot or screen recording.
- **Send a fix or feature:** fork the repo, make a branch, and open a pull
  request against `main`. Small fixes don't need an issue first. For big
  changes (a new hiding engine, large UI rework), opening an issue first saves
  everyone time.
- **Improve docs or translations:** always appreciated. English strings live in
  `hidden/en.lproj/Localizable.strings`; other languages sit next to it.

Branch names don't matter much. `feature/…`, `fix/…` and `docs/…` are a good
habit.

## Before you open a pull request

These are the only real requirements, whether a human or an AI wrote the code:

1. **It builds.** Use the `-Direct` configurations; plain `Debug`/`Release`
   are the sandboxed App Store variant and can't hide icons on macOS 27.

   ```sh
   xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway \
     -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO build
   ```

2. **Tests pass.**

   ```sh
   xcodebuild -project Tuckaway.xcodeproj -scheme Tuckaway \
     -configuration Debug-Direct CODE_SIGNING_ALLOWED=NO test
   ```

3. **You tried it on a real menu bar.** Hiding depends on the macOS version and
   your own icons, so run the app and check that the change behaves. For UI
   changes, add a screenshot or short recording to the PR.
4. **The PR says what you checked.** For example: "tested on macOS 27, notch
   MacBook, collapse and expand with 12 icons." That tells reviewers what still
   needs a look.

Useful reading, for you or your agent:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how hiding works and its
known limits, and [docs/RUNBOOK.md](docs/RUNBOOK.md) covers verification and
releases.

## Code of Conduct

### Our Pledge

We as members, contributors, and leaders pledge to make participation in our community a harassment-free experience for everyone, regardless of age, body size, visible or invisible disability, ethnicity, sex characteristics, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.

We pledge to act and interact in ways that contribute to an open, welcoming, diverse, inclusive, and healthy community.

### Our Standards

Examples of behavior that contributes to a positive environment for our community include:

* Demonstrating empathy and kindness toward other people
* Being respectful of differing opinions, viewpoints, and experiences
* Giving and gracefully accepting constructive feedback
* Accepting responsibility and apologizing to those affected by our mistakes, and learning from the experience
* Focusing on what is best not just for us as individuals, but for the overall community

Examples of unacceptable behavior include:

* The use of sexualized language or imagery, and sexual attention or
  advances of any kind
* Trolling, insulting or derogatory comments, and personal or political attacks
* Public or private harassment
* Publishing others' private information, such as a physical or email
  address, without their explicit permission
* Other conduct which could reasonably be considered inappropriate in a
  professional setting

### Enforcement Responsibilities

Community leaders are responsible for clarifying and enforcing our standards of acceptable behavior and will take appropriate and fair corrective action in response to any behavior that they deem inappropriate, threatening, offensive, or harmful.

Community leaders have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct, and will communicate reasons for moderation decisions when appropriate.

### Scope

This Code of Conduct applies within all community spaces, and also applies when an individual is officially representing the community in public spaces. Examples of representing our community include using an official e-mail address, posting via an official social media account, or acting as an appointed representative at an online or offline event.

### Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be reported to the community leaders responsible for enforcement by contacting the maintainer, [Bruno-Alumn](https://github.com/Bruno-Alumn), on GitHub. All complaints will be reviewed and investigated promptly and fairly.

All community leaders are obligated to respect the privacy and security of the reporter of any incident.

### Enforcement Guidelines

Community leaders will follow these Community Impact Guidelines in determining the consequences for any action they deem in violation of this Code of Conduct:

#### 1. Correction

**Community Impact**: Use of inappropriate language or other behavior deemed unprofessional or unwelcome in the community.

**Consequence**: A private, written warning from community leaders, providing clarity around the nature of the violation and an explanation of why the behavior was inappropriate. A public apology may be requested.

#### 2. Warning

**Community Impact**: A violation through a single incident or series of actions.

**Consequence**: A warning with consequences for continued behavior. No interaction with the people involved, including unsolicited interaction with those enforcing the Code of Conduct, for a specified period of time. This includes avoiding interactions in community spaces as well as external channels like social media. Violating these terms may lead to a temporary or permanent ban.

#### 3. Temporary Ban

**Community Impact**: A serious violation of community standards, including sustained inappropriate behavior.

**Consequence**: A temporary ban from any sort of interaction or public communication with the community for a specified period of time. No public or private interaction with the people involved, including unsolicited interaction with those enforcing the Code of Conduct, is allowed during this period. Violating these terms may lead to a permanent ban.

#### 4. Permanent Ban

**Community Impact**: Demonstrating a pattern of violation of community standards, including sustained inappropriate behavior,  harassment of an individual, or aggression toward or disparagement of classes of individuals.

**Consequence**: A permanent ban from any sort of public interaction within the project community.

### Attribution

This Code of Conduct is adapted from the [Contributor Covenant][homepage], version 2.0,
available at https://www.contributor-covenant.org/version/2/0/code_of_conduct.html.

Community Impact Guidelines were inspired by [Mozilla's code of conduct enforcement ladder](https://github.com/mozilla/diversity).

[homepage]: https://www.contributor-covenant.org

For answers to common questions about this code of conduct, see the FAQ at
https://www.contributor-covenant.org/faq. Translations are available at https://www.contributor-covenant.org/translations.
