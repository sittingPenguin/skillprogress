# SkillProgress: decisions for the school

Briefing for the data protection officer and safeguarding lead before a pilot. The software enforces the rules below, but it can't by itself make the school compliant with UK GDPR or safeguarding duties. These decisions belong to the school.

## What the app holds

- **Pupils:** display name (first name and initial) and year group. No date of birth, address or photo.
- **Video clips** of pupils practising a skill, with the date they were filmed.
- **Coach assessments:** rubric levels, written feedback and goals.
- **Private coach notes:** visible to staff only.
- **Parent accounts:** email address and display name.
- **Audit log** of who changed permissions, published, exported or deleted something.

## Decisions needed

1. **Data controller.** Confirm the school is the controller and the app provider is a processor. A data processing agreement will be needed.
2. **DPIA.** Video of children is high-risk processing, so a data protection impact assessment is expected before the pilot starts.
3. **Lawful basis.** Choose public task (part of PE teaching) or consent. Decide whether parents can opt their child out of filming, and what happens to that pupil in lessons.
4. **Who can be filmed and by whom.** Decide on school devices or staff personal phones. If personal phones are allowed, the app keeps clips out of the camera roll, but school policy should say so.
5. **Other children in shot.** Clips showing other pupils are flagged and can't be published until reviewed. Decide who reviews them and what the standard is.
6. **Retention.** Decide how long clips are kept. The default is 400 days; a common choice is the end of the following school year. Also decide what happens when a pupil leaves.
7. **Hosting.** Data is stored in the UK (Supabase, London region). Confirm that's acceptable, and review the provider's sub-processors.
8. **Parent access.** Decide who in school can invite and revoke parents. Decide how to handle separated parents and court orders; the school controls every link.
9. **Pupil logins.** These are off by default. Decide whether and from what age pupils can sign in.
10. **Requests.** Decide who handles subject access requests (the app can export everything held about a pupil) and deletion requests.
11. **Breach process.** Name the contacts and agree response times if something goes wrong.
12. **AI.** Confirm in the privacy notice that pupil videos are never used to train AI.

## Built-in safeguards

- No public links. Videos open only through links that expire after minutes, for signed-in users who are allowed to see them.
- Parents see only their own child's published feedback. Drafts and coach notes are never visible to them.
- Coaches see only the classes they're assigned to.
- Lock-screen notifications never name a child.
- Revoking access takes effect immediately.
- Every permission change, publication, export and deletion is logged.
