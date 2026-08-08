Changes since v1.0.37-70:

• 06604e3 cleanups and fixes
• 3b33353 ios sequence number waypoint
• 4a0d0c1 Add seq-maintenance Makefile targets; update plan doc
• ed6990f Add incremental HWM and cross-client E2E test coverage
• e86598b Replace JWT authorizer with Lambda authorizer for M2M token support
• 5fb506a Add Cognito M2M auth and E2E test suite
• c21bcaa Fix Terraform deploy: pre-apply VPC/Valkey before Lambda vpc_config
• 8bbffc8 Fix pull() call sites broken by hwm parameter insertion
• a1f5819 Terraform fmt fix and planning docs
• 97cf776 Fix test failures and tighten deploy gate for branch PRs
• ab05f3d Fix write-path integrity bugs in observationNumber assignment
• 5b24703 Add observationNumber sequence counter (steps 1-5)
• bfa695c build