import { useEffect, useState } from 'react';
import {
  AlertCircle,
  Bot,
  Brain,
  Check,
  CheckCircle2,
  Compass,
  Cpu,
  Eye,
  EyeOff,
  Globe,
  Key,
  Layers,
  Loader2,
  Moon,
  Pause,
  Play,
  RefreshCw,
  Server,
  Settings2,
  Sparkles,
  Sun,
  Terminal,
  Zap,
} from 'lucide-react';
import type { CodexCliStatus, State, WorkspaceState } from '../shared/types';
import { api } from './api';
import {
  setThemePreference,
  themePreference,
  type ThemePreference,
} from './theme';

interface SettingsViewProps {
  state: State;
  workspace: WorkspaceState;
  onRefresh: () => Promise<void>;
  onNavigate?: (view: 'chat' | 'tasks' | 'memories' | 'space') => void;
}

type TabKey = 'ai' | 'agents' | 'appearance' | 'diagnostics';

const MODEL_PRESETS = [
  {
    id: 'gpt-4o',
    name: 'GPT-4o',
    badge: 'Recommended',
    tag: 'Omni',
    description:
      'High-intelligence flagship model. Fast, multimodal reasoning.',
  },
  {
    id: 'gpt-4o-mini',
    name: 'GPT-4o Mini',
    badge: 'Fast & Cheap',
    tag: 'Everyday',
    description: 'Lightweight, rapid response model optimized for daily tasks.',
  },
  {
    id: 'o3-mini',
    name: 'o3-mini',
    badge: 'Reasoning',
    tag: 'Code & Math',
    description:
      'Frontier reasoning model designed for coding and complex logic.',
  },
  {
    id: 'o1',
    name: 'o1',
    badge: 'Deep Reasoning',
    tag: 'Advanced',
    description:
      'Spends time thinking before answering to solve deep problems.',
  },
  {
    id: 'gpt-4.5-preview',
    name: 'GPT-4.5',
    badge: 'Preview',
    tag: 'Frontier',
    description: 'OpenAI’s largest knowledge model with emotional intuition.',
  },
];

export function SettingsView({
  state,
  workspace,
  onRefresh,
  onNavigate,
}: SettingsViewProps) {
  const [activeTab, setActiveTab] = useState<TabKey>('ai');

  // AI & OpenAI Config state
  const [openaiApiKey, setOpenaiApiKey] = useState(
    state.settings.openaiApiKey ?? '',
  );
  const [openaiModel, setOpenaiModel] = useState(
    state.settings.openaiModel || 'gpt-4o',
  );
  const [openaiBaseUrl, setOpenaiBaseUrl] = useState(
    state.settings.openaiBaseUrl || 'https://api.openai.com/v1',
  );
  const [intelligenceApiKey, setIntelligenceApiKey] = useState(
    state.settings.intelligenceApiKey ?? '',
  );
  const [showApiKey, setShowApiKey] = useState(false);
  const [isCustomModel, setIsCustomModel] = useState(
    !MODEL_PRESETS.some(
      (m) => m.id === (state.settings.openaiModel || 'gpt-4o'),
    ),
  );
  const [customModelName, setCustomModelName] = useState(
    !MODEL_PRESETS.some(
      (m) => m.id === (state.settings.openaiModel || 'gpt-4o'),
    )
      ? state.settings.openaiModel || ''
      : '',
  );

  // Codex CLI detection state
  const [codexStatus, setCodexStatus] = useState<CodexCliStatus | null>(null);
  const [loadingCodex, setLoadingCodex] = useState(false);

  // Connection testing state
  const [testingConnection, setTestingConnection] = useState(false);
  const [testResult, setTestResult] = useState<{
    ok: boolean;
    message: string;
    latencyMs?: number;
  } | null>(null);

  // Agent preferences state
  const [paused, setPaused] = useState(state.settings.paused);
  const [researchAllowed, setResearchAllowed] = useState(
    state.settings.researchAllowed,
  );
  const [memoryAllowed, setMemoryAllowed] = useState(
    state.settings.memoryAllowed,
  );
  const [appsAllowed, setAppsAllowed] = useState(state.settings.appsAllowed);

  // Appearance state
  const [theme, setTheme] = useState<ThemePreference>(themePreference());

  // Save state
  const [saving, setSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  // Fetch Codex CLI Status
  const fetchCodexStatus = async () => {
    setLoadingCodex(true);
    try {
      const res = await api<CodexCliStatus>('/codex-cli');
      setCodexStatus(res);
    } catch {
      setCodexStatus({
        installed: false,
        binaryPath: null,
        version: null,
        loggedIn: false,
        email: null,
        plan: null,
        accountId: null,
        orgName: null,
        hasApiKey: false,
        apiKeyPreview: null,
        hasAccessToken: false,
        authMode: null,
      });
    } finally {
      setLoadingCodex(false);
    }
  };

  useEffect(() => {
    void fetchCodexStatus();
  }, []);

  // Test connection to OpenAI
  const handleTestConnection = async () => {
    setTestingConnection(true);
    setTestResult(null);
    setErrorMessage('');
    const modelToTest = isCustomModel ? customModelName.trim() : openaiModel;
    try {
      const res = await api<{
        ok: boolean;
        latencyMs?: number;
        modelsCount?: number;
        error?: string;
      }>('/settings/test-connection', 'POST', {
        apiKey: openaiApiKey.trim() || undefined,
        baseUrl: openaiBaseUrl.trim() || undefined,
        model: modelToTest || undefined,
      });

      if (res.ok) {
        setTestResult({
          ok: true,
          message: `Connected successfully! Latency: ${res.latencyMs ?? '?'}ms`,
          latencyMs: res.latencyMs,
        });
      } else {
        setTestResult({
          ok: false,
          message: res.error || 'Connection failed to OpenAI API.',
        });
      }
    } catch (err) {
      setTestResult({
        ok: false,
        message:
          err instanceof Error
            ? err.message
            : 'Connection test failed. Check your network and API credentials.',
      });
    } finally {
      setTestingConnection(false);
    }
  };

  // Save Settings
  const handleSave = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    setSaving(true);
    setSaveSuccess(false);
    setErrorMessage('');

    const effectiveModel = isCustomModel
      ? customModelName.trim()
      : openaiModel.trim();

    try {
      await api('/settings', 'PATCH', {
        openaiApiKey: openaiApiKey.trim(),
        openaiModel: effectiveModel,
        openaiBaseUrl: openaiBaseUrl.trim(),
        intelligenceApiKey: intelligenceApiKey.trim(),
        paused,
        researchAllowed,
        memoryAllowed,
        appsAllowed,
      });

      setSaveSuccess(true);
      await onRefresh();
      setTimeout(() => setSaveSuccess(false), 4000);
    } catch (err) {
      setErrorMessage(
        err instanceof Error ? err.message : 'Failed to save settings.',
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="settings-page-container">
      {/* Settings Navigation Sidebar / Tabs */}
      <div className="settings-sidebar-nav">
        <div className="settings-nav-header">
          <Settings2 size={20} className="settings-header-icon" />
          <div>
            <h3>Settings</h3>
            <span className="settings-sub">AETHER Engine & Configuration</span>
          </div>
        </div>

        <nav className="settings-tabs-list" aria-label="Settings categories">
          <button
            type="button"
            className={`settings-tab-btn ${activeTab === 'ai' ? 'active' : ''}`}
            onClick={() => setActiveTab('ai')}
          >
            <Sparkles size={16} />
            <span>AI & Models</span>
            {openaiApiKey ? (
              <span className="tab-pill tab-pill-success">Ready</span>
            ) : (
              <span className="tab-pill tab-pill-warning">Setup</span>
            )}
          </button>

          <button
            type="button"
            className={`settings-tab-btn ${activeTab === 'agents' ? 'active' : ''}`}
            onClick={() => setActiveTab('agents')}
          >
            <Bot size={16} />
            <span>Agent Preferences</span>
          </button>

          <button
            type="button"
            className={`settings-tab-btn ${activeTab === 'appearance' ? 'active' : ''}`}
            onClick={() => setActiveTab('appearance')}
          >
            <Sun size={16} />
            <span>Appearance</span>
          </button>

          <button
            type="button"
            className={`settings-tab-btn ${activeTab === 'diagnostics' ? 'active' : ''}`}
            onClick={() => setActiveTab('diagnostics')}
          >
            <Server size={16} />
            <span>System & Diagnostics</span>
          </button>
        </nav>

        <div className="settings-sidebar-footer">
          {codexStatus?.loggedIn && (
            <div className="codex-quick-status">
              <span className="status-dot-pulse online" />
              <div className="codex-quick-text">
                <strong>Codex CLI Active</strong>
                <small>{codexStatus.email || 'ChatGPT linked'}</small>
              </div>
            </div>
          )}
          {onNavigate && (
            <button
              type="button"
              className="settings-back-chat-btn"
              onClick={() => onNavigate('chat')}
            >
              ← Back to Chat
            </button>
          )}
        </div>
      </div>

      {/* Main Settings Content Area */}
      <div className="settings-main-content">
        {saveSuccess && (
          <div className="settings-alert alert-success" role="status">
            <CheckCircle2 size={18} />
            <span>
              Settings saved successfully and synchronized with environment!
            </span>
          </div>
        )}

        {errorMessage && (
          <div className="settings-alert alert-error" role="alert">
            <AlertCircle size={18} />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* TAB 1: AI & MODELS */}
        {activeTab === 'ai' && (
          <form className="settings-section-form" onSubmit={handleSave}>
            <div className="settings-section-header">
              <h2>AI Providers & Models</h2>
              <p>
                Configure OpenAI API keys, reasoning models, custom endpoints,
                and inspect automatically detected local Codex CLI credentials.
              </p>
            </div>

            {/* CODEX CLI AUTO-DETECTION CARD */}
            <div className="settings-card codex-detection-card">
              <div className="card-top-row">
                <div className="card-title-group">
                  <span className="card-icon-badge codex-badge">
                    <Terminal size={18} />
                  </span>
                  <div>
                    <h4>Codex CLI Auto-Detection</h4>
                    <span className="card-subtitle">
                      Scans local system (~/.codex/auth.json and PATH) for
                      OpenAI credentials
                    </span>
                  </div>
                </div>

                <div className="card-actions">
                  {codexStatus?.installed ? (
                    codexStatus.loggedIn ? (
                      <span className="status-badge badge-active">
                        <span className="status-dot-pulse" />
                        CLI Connected
                      </span>
                    ) : (
                      <span className="status-badge badge-warning">
                        Installed (Not Logged In)
                      </span>
                    )
                  ) : (
                    <span className="status-badge badge-muted">
                      Not Detected
                    </span>
                  )}

                  <button
                    type="button"
                    className="icon-refresh-btn"
                    title="Refresh Codex CLI detection"
                    onClick={fetchCodexStatus}
                    disabled={loadingCodex}
                  >
                    <RefreshCw
                      size={15}
                      className={loadingCodex ? 'spin' : ''}
                    />
                  </button>
                </div>
              </div>

              {codexStatus && codexStatus.installed && (
                <div className="codex-details-grid">
                  <div className="detail-item">
                    <span className="detail-label">Account / Email</span>
                    <strong className="detail-value highlight">
                      {codexStatus.email || 'Detected via auth.json'}
                    </strong>
                  </div>

                  <div className="detail-item">
                    <span className="detail-label">Subscription Plan</span>
                    <strong className="detail-value">
                      {codexStatus.plan || 'ChatGPT Plus / Pro'}
                    </strong>
                  </div>

                  {codexStatus.orgName && (
                    <div className="detail-item">
                      <span className="detail-label">Organization</span>
                      <strong className="detail-value">
                        {codexStatus.orgName}
                      </strong>
                    </div>
                  )}

                  <div className="detail-item">
                    <span className="detail-label">CLI Version & Path</span>
                    <span className="detail-code">
                      v{codexStatus.version || '0.163.0'} ·{' '}
                      {codexStatus.binaryPath}
                    </span>
                  </div>
                </div>
              )}

              {codexStatus?.loggedIn ? (
                <div className="codex-banner-info">
                  <Check size={16} className="text-success" />
                  <span>
                    Codex CLI session automatically detected for{' '}
                    <strong>{codexStatus.email}</strong>. For direct REST API
                    queries, provide your OpenAI API key below.
                  </span>
                </div>
              ) : (
                <div className="codex-banner-muted">
                  <Terminal size={15} />
                  <span>
                    To use Codex CLI with ChatGPT, install Codex via{' '}
                    <code>npm i -g @openai/codex</code> and run{' '}
                    <code>codex login</code>.
                  </span>
                </div>
              )}
            </div>

            {/* OPENAI API KEY CARD */}
            <div className="settings-card">
              <div className="card-top-row">
                <div className="card-title-group">
                  <span className="card-icon-badge openai-badge">
                    <Key size={18} />
                  </span>
                  <div>
                    <h4>OpenAI API Key</h4>
                    <span className="card-subtitle">
                      Used for autonomous Dots, agent reasoning, chat
                      completions, and tools
                    </span>
                  </div>
                </div>

                {openaiApiKey ? (
                  <span className="status-badge badge-active">Configured</span>
                ) : (
                  <span className="status-badge badge-warning">Required</span>
                )}
              </div>

              <div className="form-group">
                <label htmlFor="openai-api-key" className="form-label">
                  API Key
                </label>
                <div className="password-input-wrapper">
                  <input
                    id="openai-api-key"
                    type={showApiKey ? 'text' : 'password'}
                    value={openaiApiKey}
                    placeholder="sk-proj-..."
                    autoComplete="off"
                    spellCheck="false"
                    onChange={(e) => setOpenaiApiKey(e.target.value)}
                  />
                  <button
                    type="button"
                    className="password-toggle-btn"
                    aria-label={showApiKey ? 'Hide API key' : 'Show API key'}
                    onClick={() => setShowApiKey(!showApiKey)}
                  >
                    {showApiKey ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
                <p className="form-hint">
                  Your key is persisted securely in your local SQLite store and
                  updated in your local <code>.env</code>.
                </p>
              </div>

              {/* MODEL SELECTOR */}
              <div className="form-group">
                <label className="form-label">Active Model</label>
                <div className="model-cards-grid">
                  {MODEL_PRESETS.map((m) => {
                    const isSelected = !isCustomModel && openaiModel === m.id;
                    return (
                      <div
                        key={m.id}
                        className={`model-card-item ${isSelected ? 'selected' : ''}`}
                        onClick={() => {
                          setIsCustomModel(false);
                          setOpenaiModel(m.id);
                        }}
                      >
                        <div className="model-card-header">
                          <strong>{m.name}</strong>
                          <span className="model-badge">{m.badge}</span>
                        </div>
                        <p className="model-card-desc">{m.description}</p>
                        <div className="model-card-tag">{m.tag}</div>
                      </div>
                    );
                  })}

                  {/* Custom Model Option */}
                  <div
                    className={`model-card-item ${isCustomModel ? 'selected' : ''}`}
                    onClick={() => setIsCustomModel(true)}
                  >
                    <div className="model-card-header">
                      <strong>Custom Model</strong>
                      <span className="model-badge">Custom</span>
                    </div>
                    <p className="model-card-desc">
                      Specify any compatible model ID (e.g. fine-tuned, Ollama,
                      OpenRouter).
                    </p>
                    <div className="model-card-tag">Self-hosted / Other</div>
                  </div>
                </div>

                {isCustomModel && (
                  <div className="custom-model-input-area">
                    <label htmlFor="custom-model-name" className="form-label">
                      Custom Model Identifier
                    </label>
                    <input
                      id="custom-model-name"
                      type="text"
                      placeholder="e.g. gpt-4-turbo or meta-llama/llama-3.3-70b-instruct"
                      value={customModelName}
                      onChange={(e) => setCustomModelName(e.target.value)}
                    />
                  </div>
                )}
              </div>

              {/* BASE URL (Custom endpoints) */}
              <div className="form-group">
                <label htmlFor="openai-base-url" className="form-label">
                  Base URL (Endpoint)
                </label>
                <div className="input-with-icon">
                  <Globe size={16} className="input-icon" />
                  <input
                    id="openai-base-url"
                    type="url"
                    value={openaiBaseUrl}
                    placeholder="https://api.openai.com/v1"
                    onChange={(e) => setOpenaiBaseUrl(e.target.value)}
                  />
                </div>
                <p className="form-hint">
                  Default: <code>https://api.openai.com/v1</code>. You can point
                  this to local Ollama (<code>http://localhost:11434/v1</code>),
                  OpenRouter, or Azure.
                </p>
              </div>

              {/* TEST CONNECTION & STATUS */}
              <div className="test-connection-bar">
                <button
                  type="button"
                  className="test-conn-btn"
                  onClick={handleTestConnection}
                  disabled={
                    testingConnection ||
                    (!openaiApiKey.trim() && !state.settings.openaiApiKey)
                  }
                >
                  {testingConnection ? (
                    <>
                      <Loader2 size={16} className="spin" />
                      <span>Testing Endpoint…</span>
                    </>
                  ) : (
                    <>
                      <Zap size={16} />
                      <span>Test Connection</span>
                    </>
                  )}
                </button>

                {testResult && (
                  <div
                    className={`test-feedback-pill ${testResult.ok ? 'success' : 'failure'}`}
                  >
                    {testResult.ok ? (
                      <CheckCircle2 size={16} />
                    ) : (
                      <AlertCircle size={16} />
                    )}
                    <span>{testResult.message}</span>
                  </div>
                )}
              </div>
            </div>

            {/* COPILOTKIT INTELLIGENCE KEY (OPTIONAL) */}
            <div className="settings-card optional-card">
              <div className="card-top-row">
                <div className="card-title-group">
                  <span className="card-icon-badge cpk-badge">
                    <Brain size={18} />
                  </span>
                  <div>
                    <h4>CopilotKit Intelligence Key (Optional)</h4>
                    <span className="card-subtitle">
                      Cloud-based cross-device memory synchronization, learning,
                      and skill delivery
                    </span>
                  </div>
                </div>
              </div>

              <div className="form-group">
                <label htmlFor="cpk-key" className="form-label">
                  Intelligence API Key
                </label>
                <input
                  id="cpk-key"
                  type="password"
                  placeholder="ck_..."
                  value={intelligenceApiKey}
                  onChange={(e) => setIntelligenceApiKey(e.target.value)}
                />
                <p className="form-hint">
                  Optional. If omitted, AETHER operates locally with your direct
                  OpenAI API key.
                </p>
              </div>
            </div>

            {/* SUBMIT BUTTON BAR */}
            <div className="settings-sticky-actions">
              <button
                type="submit"
                className="primary settings-save-btn"
                disabled={saving}
              >
                {saving ? (
                  <>
                    <Loader2 size={16} className="spin" />
                    <span>Saving Settings…</span>
                  </>
                ) : (
                  <>
                    <Check size={16} />
                    <span>Save AI Settings</span>
                  </>
                )}
              </button>
            </div>
          </form>
        )}

        {/* TAB 2: AGENT PREFERENCES */}
        {activeTab === 'agents' && (
          <form className="settings-section-form" onSubmit={handleSave}>
            <div className="settings-section-header">
              <h2>Agent Preferences & Safety</h2>
              <p>
                Configure permissions and capabilities across all Dots in your
                workspace.
              </p>
            </div>

            <div className="settings-card">
              <div className="toggle-setting-row">
                <div className="toggle-info">
                  <div className="toggle-title-line">
                    {paused ? (
                      <Pause size={18} className="text-warning" />
                    ) : (
                      <Play size={18} className="text-success" />
                    )}
                    <strong>Master Pause</strong>
                  </div>
                  <p>
                    When paused, all background compute stops, autonomous Dots
                    wait, and scheduled tasks are deferred.
                  </p>
                </div>
                <label className="switch-label">
                  <input
                    type="checkbox"
                    checked={paused}
                    onChange={(e) => setPaused(e.target.checked)}
                  />
                  <span className="switch-slider" />
                </label>
              </div>

              <div className="setting-divider" />

              <div className="toggle-setting-row">
                <div className="toggle-info">
                  <div className="toggle-title-line">
                    <Globe size={18} />
                    <strong>Web Research Allowed</strong>
                  </div>
                  <p>
                    Permit Dots to use Parallel or DuckDuckGo web search to
                    gather live information.
                  </p>
                </div>
                <label className="switch-label">
                  <input
                    type="checkbox"
                    checked={researchAllowed}
                    onChange={(e) => setResearchAllowed(e.target.checked)}
                  />
                  <span className="switch-slider" />
                </label>
              </div>

              <div className="setting-divider" />

              <div className="toggle-setting-row">
                <div className="toggle-info">
                  <div className="toggle-title-line">
                    <Layers size={18} />
                    <strong>Persistent Memories</strong>
                  </div>
                  <p>
                    Allow Dots to recall your explicit user preferences across
                    conversations.
                  </p>
                </div>
                <label className="switch-label">
                  <input
                    type="checkbox"
                    checked={memoryAllowed}
                    onChange={(e) => setMemoryAllowed(e.target.checked)}
                  />
                  <span className="switch-slider" />
                </label>
              </div>

              <div className="setting-divider" />

              <div className="toggle-setting-row">
                <div className="toggle-info">
                  <div className="toggle-title-line">
                    <Cpu size={18} />
                    <strong>Apps & Composio Integrations</strong>
                  </div>
                  <p>
                    Enable third-party app tool execution (GitHub, Slack,
                    linear, browser automation) when configured.
                  </p>
                </div>
                <label className="switch-label">
                  <input
                    type="checkbox"
                    checked={appsAllowed}
                    onChange={(e) => setAppsAllowed(e.target.checked)}
                  />
                  <span className="switch-slider" />
                </label>
              </div>
            </div>

            <div className="settings-sticky-actions">
              <button
                type="submit"
                className="primary settings-save-btn"
                disabled={saving}
              >
                {saving ? 'Saving…' : 'Save Agent Preferences'}
              </button>
            </div>
          </form>
        )}

        {/* TAB 3: APPEARANCE */}
        {activeTab === 'appearance' && (
          <div className="settings-section-form">
            <div className="settings-section-header">
              <h2>Interface & Theme</h2>
              <p>Choose your workspace theme and display preferences.</p>
            </div>

            <div className="settings-card">
              <h4>Theme Preference</h4>
              <div className="theme-options-grid">
                {[
                  {
                    id: 'system' as ThemePreference,
                    label: 'System Match',
                    desc: 'Follows macOS / system color scheme automatically',
                    icon: <Compass size={22} />,
                  },
                  {
                    id: 'light' as ThemePreference,
                    label: 'Warm Light',
                    desc: 'Clean, soothing paper aesthetic with crisp typography',
                    icon: <Sun size={22} />,
                  },
                  {
                    id: 'dark' as ThemePreference,
                    label: 'Deep Dark',
                    desc: 'High contrast dark mode designed for focus and low light',
                    icon: <Moon size={22} />,
                  },
                ].map((item) => (
                  <div
                    key={item.id}
                    className={`theme-card ${theme === item.id ? 'active' : ''}`}
                    onClick={() => {
                      setTheme(item.id);
                      setThemePreference(item.id);
                    }}
                  >
                    <div className="theme-card-icon">{item.icon}</div>
                    <strong>{item.label}</strong>
                    <p>{item.desc}</p>
                    {theme === item.id && (
                      <span className="theme-check">
                        <Check size={14} />
                      </span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* TAB 4: SYSTEM & DIAGNOSTICS */}
        {activeTab === 'diagnostics' && (
          <div className="settings-section-form">
            <div className="settings-section-header">
              <h2>System Diagnostics</h2>
              <p>
                Inspect local services, database health, and environment
                bindings.
              </p>
            </div>

            <div className="settings-card">
              <h4>Service Status</h4>
              <div className="diagnostics-table">
                <div className="diag-row">
                  <span className="diag-label">Database Store</span>
                  <span className="diag-val success">
                    <CheckCircle2 size={14} /> SQLite (AETHER-web/store.db)
                  </span>
                </div>

                <div className="diag-row">
                  <span className="diag-label">OpenAI API Connection</span>
                  <span
                    className={`diag-val ${state.settings.openaiApiKey ? 'success' : 'warning'}`}
                  >
                    {state.settings.openaiApiKey
                      ? `Configured (${state.settings.openaiModel || 'gpt-4o'})`
                      : 'Missing OPENAI_API_KEY'}
                  </span>
                </div>

                <div className="diag-row">
                  <span className="diag-label">Codex CLI Detection</span>
                  <span
                    className={`diag-val ${codexStatus?.loggedIn ? 'success' : 'muted'}`}
                  >
                    {codexStatus?.loggedIn
                      ? `Active · ${codexStatus.email}`
                      : codexStatus?.installed
                        ? 'Installed (Unauthenticated)'
                        : 'Not detected on PATH'}
                  </span>
                </div>

                <div className="diag-row">
                  <span className="diag-label">Slack Bot Channel</span>
                  <span
                    className={`diag-val ${workspace.setup.slack === 'online' ? 'success' : 'muted'}`}
                  >
                    {workspace.setup.slack.replaceAll('_', ' ')}
                  </span>
                </div>

                <div className="diag-row">
                  <span className="diag-label">Voice / Realtime</span>
                  <span
                    className={`diag-val ${workspace.setup.voice ? 'success' : 'muted'}`}
                  >
                    {workspace.setup.voice
                      ? 'Online (VOICE_API_KEY ready)'
                      : 'Not configured'}
                  </span>
                </div>

                <div className="diag-row">
                  <span className="diag-label">Spaces & Dots Count</span>
                  <span className="diag-val">
                    {workspace.spaces.length} Spaces · {workspace.dots.length}{' '}
                    Dots
                  </span>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
