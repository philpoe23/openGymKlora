# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **The trainer (admin):** a newly certified personal trainer who runs the instance. She trains herself
  and uses the app for her own sessions, and she manages her clients: who they are, what they lifted,
  what to give them next.
- **Clients:** her personal-training clients. Each has their own account, logs their own workouts on
  their phone in the gym, follows routines she assigns, and checks in with her between sessions.

## Product Purpose

Klora Fitness is a self-hosted gym tracker turned into a one-trainer coaching app. It exists so one
trainer can train herself and run her client book in the same place, without a third-party platform
owning her clients' data. Success: her clients log consistently, she can see at a glance who is
progressing and who has gone quiet, and assigning the next block takes minutes.

## Positioning

Owned by the trainer, not rented: her app, her name, her server (Coolify), her clients' data in a
folder she controls. Built on a serious training engine (progression rules, 1RM, recovery model,
1,324-exercise library) rather than a generic habit tracker.

## Operating Context

- Clients use it mid-session on a phone, between sets, often one-handed; installable PWA.
- The trainer uses it on phone and laptop: her own workouts in the gym, client review and
  programming at a desk.
- Hosted on Coolify with the existing Docker compose stack (`api` + `web`); data is the JSON files
  in `./data` (no external database).

## Capabilities and Constraints

- Existing: passkey + password sign-in/sign-up, invite-only sign-up, per-user workout state,
  progression engine, stats, history, operator admin (`ADMIN_UIDS`).
- v1 trainer features: client list with progress, assign routines to a client, private notes per
  client, two-way check-ins (client ↔ trainer), invite clients.
- Clients log their own workouts; the trainer reads their data and pushes routines to them.
- Dependency-light is a hard constraint (React + Router + Zustand only; api has two deps).
- Trainer pages are English-only for now; client-facing strings go through the i18n catalogue.

## Brand Commitments

- Name: **Klora Fitness**.
- Visual brief pinned by the user: pink pastel, modern, clean, stands out.

## Evidence on Hand

- No logo, photography, testimonials, pricing or client list yet. Do not fabricate any of them.

## Product Principles

1. The client in the gym comes first: logging a set is never slower than before.
2. One trainer, many clients: every trainer screen answers "who needs me today?"
3. Her data, her server: nothing leaves the instance.
4. Training logic stays tested: anything that decides what is lifted next has a unit test.
