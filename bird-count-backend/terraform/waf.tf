# Optional WAF on the CloudFront distribution (enable_waf, default off).
# When enabled (~$6-8/mo): per-IP rate limiting + AWS managed common rules.

resource "aws_wafv2_web_acl" "web" {
  count = var.enable_waf ? 1 : 0

  name  = "${local.project_name}-${var.environment}-web"
  scope = "CLOUDFRONT" # must be us-east-1 (we are)

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000 # requests per 5 minutes per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.project_name}-${var.environment}-web"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}
