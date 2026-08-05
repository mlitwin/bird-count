# Beta Distribution: S3 + CloudFront Terraform Plan

Ad-Hoc iOS builds require an HTTPS host that serves `.plist` manifest files as
`text/xml` — a requirement GitHub Pages cannot meet. This document sketches the
Terraform additions needed to host beta builds on AWS, matching the patterns
already in use by the rest of the backend stack.

## Architecture

```
developer (mac)
  └─ make fastlane-beta
        └─ fastlane beta lane
              ├─ builds BirdCount-<ver>-<build>.ipa
              ├─ creates BirdCount-<ver>-<build>.plist (manifest)
              └─ aws s3 sync docs/builds/ → s3://birdcount-beta-builds/
                    └─ CloudFront (HTTPS)
                          └─ iOS device: itms-services:// install
```

The beta S3 bucket is **separate** from the existing web-app bucket so builds
never interfere with web deploys, have independent cache settings, and can be
wiped/retained independently.

CloudFront is needed in front of S3 for two reasons:
1. Apple requires HTTPS with a CA-trusted certificate; S3 website endpoints use
   HTTP or unsigned TLS.
2. CloudFront response-header policies let us force `Content-Type: text/xml` on
   `.plist` objects regardless of what S3 stores.

---

## New Module: `modules/beta-dist/`

Add three files under `bird-count-backend/terraform/modules/beta-dist/`.

### `modules/beta-dist/variables.tf`

```hcl
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
```

### `modules/beta-dist/main.tf`

```hcl
# ── S3 bucket ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "beta" {
  bucket = "${var.project_name}-${var.environment}-beta-builds"
  tags   = merge(var.tags, { Name = "${var.project_name}-${var.environment}-beta-builds" })
}

resource "aws_s3_bucket_versioning" "beta" {
  bucket = aws_s3_bucket.beta.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "beta" {
  bucket = aws_s3_bucket.beta.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "beta" {
  bucket                  = aws_s3_bucket.beta.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CloudFront Origin Access Control ──────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "beta" {
  name                              = "${var.project_name}-${var.environment}-beta-oac"
  description                       = "OAC for beta builds bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── Response-header policy: force correct MIME types ──────────────────────────
#
# Apple's OTA mechanism requires:
#   .plist  → Content-Type: text/xml
#   .ipa    → Content-Type: application/octet-stream
#
# S3 stores whatever content-type was set at upload time. The response-header
# policy here enforces the plist requirement at the CDN layer so uploads don't
# need to be perfectly typed.

resource "aws_cloudfront_response_headers_policy" "beta" {
  name    = "${var.project_name}-${var.environment}-beta-headers"
  comment = "Force text/xml for .plist; application/octet-stream for .ipa"

  # CloudFront cannot conditionally set Content-Type per extension via a single
  # response-header policy — Content-Type overrides apply to ALL paths under
  # that cache behavior. The correct approach is TWO ordered cache behaviors
  # (see distribution below), each with its own response-header policy.
}

resource "aws_cloudfront_response_headers_policy" "plist" {
  name    = "${var.project_name}-${var.environment}-beta-plist-headers"
  comment = "Force Content-Type: text/xml for Apple OTA manifest files"

  custom_headers_config {
    items {
      header   = "Content-Type"
      value    = "text/xml"
      override = true
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "ipa" {
  name    = "${var.project_name}-${var.environment}-beta-ipa-headers"
  comment = "Force Content-Type: application/octet-stream for IPA files"

  custom_headers_config {
    items {
      header   = "Content-Disposition"
      value    = "attachment"
      override = true
    }
  }
}

# ── CloudFront distribution ───────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "beta" {
  origin {
    domain_name              = aws_s3_bucket.beta.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.beta.id
    origin_id                = "S3-${aws_s3_bucket.beta.bucket}"
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = "BirdCount beta build distribution"
  price_class     = "PriceClass_100"

  # ── .plist files: force text/xml ──────────────────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "*.plist"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.beta.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    response_headers_policy_id = aws_cloudfront_response_headers_policy.plist.id

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    # Short TTL on manifests so a newly-uploaded build is immediately available
    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 600
  }

  # ── .ipa files: attachment header, longer cache ────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "*.ipa"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.beta.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    response_headers_policy_id = aws_cloudfront_response_headers_policy.ipa.id

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800
  }

  # ── default: index.html, builds.json, etc. ─────────────────────────────────
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.beta.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

# ── Bucket policy: allow CloudFront OAC only ──────────────────────────────────

resource "aws_s3_bucket_policy" "beta" {
  bucket = aws_s3_bucket.beta.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.beta.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.beta.arn
        }
      }
    }]
  })
}
```

### `modules/beta-dist/outputs.tf`

```hcl
output "bucket_name" {
  description = "S3 bucket for beta build artifacts"
  value       = aws_s3_bucket.beta.bucket
}

output "cloudfront_domain_name" {
  description = "CloudFront domain — use as ADHOC_BASE_URL in fastlane beta"
  value       = aws_cloudfront_distribution.beta.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — needed for cache invalidations"
  value       = aws_cloudfront_distribution.beta.id
}
```

---

## Wire into `main.tf`

Add the module call. Beta builds are only needed in prod (or a shared
environment) — gate with `count` if you want to skip it in dev:

```hcl
module "beta_dist" {
  source = "./modules/beta-dist"

  project_name = local.project_name
  environment  = var.environment
  tags         = local.common_tags
}
```

Add to `outputs.tf`:

```hcl
output "beta_bucket_name" {
  description = "S3 bucket for iOS beta builds"
  value       = module.beta_dist.bucket_name
}

output "beta_cloudfront_domain" {
  description = "CloudFront domain for iOS beta distribution"
  value       = module.beta_dist.cloudfront_domain_name
}

output "beta_cloudfront_distribution_id" {
  value = module.beta_dist.cloudfront_distribution_id
}
```

---

## Upload from Fastlane

After `gym` produces the IPA and manifest, replace the `FileUtils.cp` calls in
the `beta` lane with an `aws s3 sync` that sets correct content types:

```ruby
# In fastlane/Fastfile, beta lane, after build succeeds:
sh(
  "aws s3 cp build/BirdCount-AdHoc.ipa " \
  "s3://#{ENV['BETA_S3_BUCKET']}/#{build_filename}.ipa " \
  "--content-type application/octet-stream"
)
sh(
  "aws s3 cp docs/builds/#{build_filename}.plist " \
  "s3://#{ENV['BETA_S3_BUCKET']}/#{build_filename}.plist " \
  "--content-type text/xml"
)
sh(
  "aws s3 cp docs/builds/builds.json " \
  "s3://#{ENV['BETA_S3_BUCKET']}/builds.json " \
  "--content-type application/json " \
  "--cache-control 'no-cache'"
)
# Invalidate the manifest and index so devices see the new build immediately
sh(
  "aws cloudfront create-invalidation " \
  "--distribution-id #{ENV['BETA_CF_DISTRIBUTION_ID']} " \
  "--paths '/builds.json' '/#{build_filename}.plist'"
)
```

Set these env vars (add to `apple.env` in 1Password or a new `beta.env`):

```
BETA_S3_BUCKET=birdcount-prod-beta-builds
BETA_CF_DISTRIBUTION_ID=<from terraform output beta_cloudfront_distribution_id>
ADHOC_BASE_URL=https://<from terraform output beta_cloudfront_domain>
```

Then invoke with:
```
make fastlane-beta   # already wraps: bundle exec fastlane beta
```

---

## Email / Install Flow

The install URL pattern the `beta` lane already generates:
```
itms-services://?action=download-manifest&url=https%3A%2F%2F<cf-domain>%2FBirdCount-1.0.37-70.plist
```

Options for getting that to beta users:
1. **Direct email** — paste the `itms-services://` URL; it renders as a tappable
   link in Mail on iOS.
2. **Install page** — add `docs/builds/index.html` that reads `builds.json` and
   renders an "Install" button per build. Host `index.html` in the same S3
   bucket; share `https://<cf-domain>/index.html`.
3. **Simple redirect page** — a one-liner page that immediately redirects to the
   `itms-services://` URL, so you can email a plain HTTPS link that auto-launches
   the iOS installer.

Option 2 is the most useful for ongoing distribution: one stable URL, always
shows the current build list.

---

## Cost Estimate

| Resource | Monthly cost |
|----------|-------------|
| S3 storage (10 builds × ~10 MB) | < $0.01 |
| S3 GET requests (light usage) | < $0.01 |
| CloudFront (PriceClass_100, ~100 requests/mo) | < $0.01 |
| **Total** | **~$0 / mo** |

The budget alarm at $20/mo in `bootstrap/main.tf` covers this with no changes.

---

## Prerequisites Before Running

1. **Create `BirdCountAdHoc` provisioning profile** in Apple Developer Portal:
   - Certificates, Identifiers & Profiles → Provisioning Profiles → + → Ad Hoc
   - Bundle ID: `org.antoninus.birdcount.app`
   - Select your distribution certificate
   - Register target device UDIDs
   - Name exactly: `BirdCountAdHoc`
   - Download and install in Xcode

2. **Run `terraform apply`** to create the bucket and distribution
   (takes ~5 min for CloudFront propagation)

3. **Set env vars** (`BETA_S3_BUCKET`, `BETA_CF_DISTRIBUTION_ID`, `ADHOC_BASE_URL`)

4. **Run `make fastlane-beta`** — first successful run proves the pipeline end
   to end.
