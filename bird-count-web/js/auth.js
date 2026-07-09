// auth.js — PKCE auth flow against Cognito hosted UI.
// Tokens stored in sessionStorage (die with tab — acceptable for a report viewer).

import { config } from './config.js';

const TOKEN_KEY = 'bc_tokens';
const VERIFIER_KEY = 'bc_pkce_verifier';

// -- PKCE helpers --

function randomBase64url(byteLen) {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLen));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

async function sha256Base64url(str) {
  const encoded = new TextEncoder().encode(str);
  const hash = await crypto.subtle.digest('SHA-256', encoded);
  return btoa(String.fromCharCode(...new Uint8Array(hash)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

// -- Public API --

export function isLoggedIn() {
  return _loadTokens() !== null;
}

export async function login() {
  const verifier = randomBase64url(64);
  const challenge = await sha256Base64url(verifier);
  sessionStorage.setItem(VERIFIER_KEY, verifier);

  const url = new URL(`https://${config.hostedUIDomain}/oauth2/authorize`);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', config.webClientId);
  url.searchParams.set('redirect_uri', config.redirectURI);
  url.searchParams.set('code_challenge_method', 'S256');
  url.searchParams.set('code_challenge', challenge);
  url.searchParams.set('scope', 'openid');
  window.location.href = url.toString();
}

/** Exchange the ?code= callback param for tokens. Returns true if a code was present. */
export async function handleCallback() {
  const params = new URLSearchParams(window.location.search);

  // e.g. the user cancelled the Apple sign-in sheet
  const error = params.get('error');
  if (error) {
    window.history.replaceState({}, '', window.location.pathname + window.location.hash);
    throw new Error(`Sign-in failed: ${error}`);
  }

  const code = params.get('code');
  if (!code) return false;

  const verifier = sessionStorage.getItem(VERIFIER_KEY);
  if (!verifier) throw new Error('Missing PKCE verifier — was login() called in this tab?');

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: config.webClientId,
    code,
    redirect_uri: config.redirectURI,
    code_verifier: verifier,
  });

  const res = await fetch(`https://${config.hostedUIDomain}/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status}`);

  const tokens = await res.json();
  sessionStorage.removeItem(VERIFIER_KEY);
  _saveTokens(tokens);

  // Remove ?code= from the URL bar without a reload
  window.history.replaceState({}, '', window.location.pathname + window.location.hash);
  return true;
}

/**
 * Return a valid access token, silently refreshing if within 60 s of expiry.
 * Returns null if unauthenticated or refresh fails (caller should show sign-in).
 */
export async function accessToken() {
  const tokens = _loadTokens();
  if (!tokens) return null;

  if (Date.now() < (tokens._expiresAt ?? 0) - 60_000) {
    return tokens.access_token;
  }

  try {
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: config.webClientId,
      refresh_token: tokens.refresh_token,
    });
    const res = await fetch(`https://${config.hostedUIDomain}/oauth2/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
    if (!res.ok) throw new Error('Refresh failed');

    const refreshed = await res.json();
    // Cognito doesn't return a new refresh_token on refresh; carry the old one forward
    refreshed.refresh_token ??= tokens.refresh_token;
    _saveTokens(refreshed);
    return refreshed.access_token;
  } catch {
    sessionStorage.removeItem(TOKEN_KEY);
    return null;
  }
}

export function logout() {
  sessionStorage.removeItem(TOKEN_KEY);
  const url = new URL(`https://${config.hostedUIDomain}/logout`);
  url.searchParams.set('client_id', config.webClientId);
  url.searchParams.set('logout_uri', config.redirectURI);
  window.location.href = url.toString();
}

// -- Internal --

function _saveTokens(tokens) {
  const expiresAt = Date.now() + (tokens.expires_in ?? 3600) * 1000;
  sessionStorage.setItem(TOKEN_KEY, JSON.stringify({ ...tokens, _expiresAt: expiresAt }));
}

function _loadTokens() {
  try {
    const raw = sessionStorage.getItem(TOKEN_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}
