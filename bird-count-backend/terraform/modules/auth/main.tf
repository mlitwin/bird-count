# Cognito user pool federated with Sign in with Apple.
# Sign-in happens only through the hosted UI -> Apple; native sign-up is off.

resource "aws_cognito_user_pool" "users" {
  name = "${var.project_name}-${var.environment}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  deletion_protection = var.environment == "prod" ? "ACTIVE" : "INACTIVE"

  tags = var.tags
}

resource "aws_cognito_identity_provider" "apple" {
  user_pool_id  = aws_cognito_user_pool.users.id
  provider_name = "SignInWithApple"
  provider_type = "SignInWithApple"

  provider_details = {
    client_id        = var.apple_services_id
    team_id          = var.apple_team_id
    key_id           = var.apple_key_id
    private_key      = var.apple_private_key
    authorize_scopes = "email name"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

resource "aws_cognito_user_pool_client" "ios" {
  name         = "${var.project_name}-${var.environment}-ios"
  user_pool_id = aws_cognito_user_pool.users.id

  # Public client: authorization code + PKCE, no secret (ASWebAuthenticationSession)
  generate_secret                      = false
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = [aws_cognito_identity_provider.apple.provider_name]

  callback_urls = var.callback_urls
  logout_urls   = var.callback_urls

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 90 # days

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "hosted_ui" {
  domain       = "${var.project_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.users.id
}
