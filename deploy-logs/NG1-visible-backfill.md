# NG-1 deploy gate — `visible` backfill required before firestore.rules deploy

**Status: BLOCKING the firestore.rules deploy. Do not deploy the rule change until the backfill below is confirmed.**

## What changed
`firestore.rules` posts read rule now requires `visible == true` for non-owner public reads
(was: any `isEffectivelyPublic` post readable). This closes the NG-1 hole where a brand-new
public post was readable by other users **before** the `moderatePost` Cloud Function cleared it.

## Why a backfill is needed
- New posts are created with `visible:false` (enforced by the create rule) and flipped to
  `visible:true` by `moderatePost` after review — so new posts behave correctly.
- **Risk:** any already-approved legacy post that does **not** have `visible:true` set will
  become invisible to everyone except its owner the moment this rule deploys. If a large share
  of the live corpus predates the moderation pipeline, deploying without a backfill **blacks out
  the feed**.

## Required pre-deploy step
1. Determine how many `posts` lack `visible == true`:
   - Query/count `posts` where `visible != true` (and not `removed`/`flaggedForReview`).
2. Backfill `visible = true` on all legacy posts that are already approved
   (i.e. `removed != true` and `flaggedForReview != true`), via an admin script / one-off CF.
3. Re-count to confirm only genuinely-pending posts remain `visible != true`.
4. Then deploy:
   ```sh
   # from repo root
   firebase deploy --only firestore:rules 2>&1 | tee deploy-logs/firestore-rules-NG1-$(date +%Y%m%d-%H%M%S).log
   ```

## If the corpus is already fully `visible:true`
If a check confirms every live, non-removed post already has `visible:true`, the backfill is a
no-op and the rule can be deployed immediately.
