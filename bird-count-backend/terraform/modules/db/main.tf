# DynamoDB single-table store for the observation ledger (Phase 2).
# Table birdcount-data-<env>: PK pk (scope), SK sk ("obs#<uuid>"),
# GSI "changes" (pk, serverUpdatedAt) for delta queries.
