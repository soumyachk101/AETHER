import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';

export interface CodexCliStatus {
  installed: boolean;
  binaryPath: string | null;
  version: string | null;
  loggedIn: boolean;
  email: string | null;
  plan: string | null;
  accountId: string | null;
  orgName: string | null;
  hasApiKey: boolean;
  apiKeyPreview: string | null;
  hasAccessToken: boolean;
  authMode: string | null;
}

export function detectCodexCli(): CodexCliStatus {
  const home = os.homedir();
  const candidates = [
    '/Users/soumyachakraborty/.npm-global/bin/codex',
    path.join(home, '.npm-global', 'bin', 'codex'),
    '/usr/local/bin/codex',
    '/opt/homebrew/bin/codex',
    path.join(home, '.local', 'bin', 'codex'),
    '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex',
  ];

  let binaryPath: string | null = null;
  try {
    const which = execSync('which codex', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (which) binaryPath = which;
  } catch {
    // Ignore error if not found in default PATH
  }

  if (!binaryPath) {
    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) {
        binaryPath = candidate;
        break;
      }
    }
  }

  let version: string | null = null;
  if (binaryPath) {
    try {
      version = execSync(`"${binaryPath}" --version`, {
        encoding: 'utf8',
        timeout: 3000,
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
    } catch {
      version = 'Installed';
    }
  }

  const authFile = path.join(home, '.codex', 'auth.json');
  let authData: Record<string, unknown> | null = null;
  if (fs.existsSync(authFile)) {
    try {
      authData = JSON.parse(fs.readFileSync(authFile, 'utf8'));
    } catch {
      // Ignore parse error
    }
  }

  let email: string | null = null;
  let plan: string | null = null;
  let accountId: string | null = null;
  let orgName: string | null = null;
  let hasApiKey = false;
  let apiKeyPreview: string | null = null;
  let hasAccessToken = false;
  let loggedIn = false;

  if (authData) {
    const rawApiKey = authData.OPENAI_API_KEY;
    if (rawApiKey && typeof rawApiKey === 'string' && rawApiKey.trim().length > 0) {
      hasApiKey = true;
      loggedIn = true;
      apiKeyPreview = `${rawApiKey.slice(0, 7)}...${rawApiKey.slice(-4)}`;
    }

    const tokens = authData.tokens as Record<string, unknown> | undefined;
    if (tokens?.access_token) {
      hasAccessToken = true;
      loggedIn = true;
    }

    if (tokens?.id_token && typeof tokens.id_token === 'string') {
      try {
        const parts = tokens.id_token.split('.');
        if (parts.length >= 2) {
          const payloadStr = Buffer.from(parts[1], 'base64').toString('utf8');
          const claims = JSON.parse(payloadStr) as {
            email?: string;
            'https://api.openai.com/auth'?: {
              chatgpt_plan_type?: string;
              chatgpt_account_id?: string;
              organizations?: Array<{ title?: string }>;
            };
          };

          email = claims.email || null;
          const authClaim = claims['https://api.openai.com/auth'];
          if (authClaim) {
            const rawPlan = authClaim.chatgpt_plan_type;
            if (rawPlan) {
              plan = rawPlan === 'go' ? 'ChatGPT Go' : rawPlan[0].toUpperCase() + rawPlan.slice(1);
            }
            accountId = authClaim.chatgpt_account_id || null;
            if (authClaim.organizations && authClaim.organizations[0]?.title) {
              orgName = authClaim.organizations[0].title;
            }
          }
        }
      } catch {
        // Ignore token decode error
      }
    }
  }

  return {
    installed: !!binaryPath,
    binaryPath,
    version,
    loggedIn,
    email,
    plan,
    accountId,
    orgName,
    hasApiKey,
    apiKeyPreview,
    hasAccessToken,
    authMode: (authData?.auth_mode as string) || (hasApiKey ? 'api_key' : hasAccessToken ? 'chatgpt' : null),
  };
}
