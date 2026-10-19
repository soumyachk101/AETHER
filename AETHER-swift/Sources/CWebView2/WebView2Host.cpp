#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <wrl.h>
#include <WebView2.h>
#include "CWebView2.h"

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {
ComPtr<ICoreWebView2Controller> controller;
ComPtr<ICoreWebView2> webView;
HWND windowHandle = nullptr;
HWND statusHandle = nullptr;
std::wstring trustedOrigin;

std::wstring widen(const char *text) {
    if (!text || !*text) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, nullptr, 0);
    if (length <= 1) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result.data(), length);
    result.pop_back();
    return result;
}

void setStatus(const std::wstring &message) {
    if (statusHandle) {
        SetWindowTextW(statusHandle, message.c_str());
        ShowWindow(statusHandle, SW_SHOW);
    }
}

std::wstring originFor(const std::wstring &url) {
    const auto scheme = url.find(L"://");
    if (scheme == std::wstring::npos) return {};
    const auto path = url.find(L'/', scheme + 3);
    return url.substr(0, path == std::wstring::npos ? url.size() : path);
}

bool isTrustedUri(const std::wstring &uri) {
    if (trustedOrigin.empty() || uri.compare(0, trustedOrigin.size(), trustedOrigin) != 0) return false;
    if (uri.size() == trustedOrigin.size()) return true;
    const wchar_t boundary = uri[trustedOrigin.size()];
    return boundary == L'/' || boundary == L'?' || boundary == L'#';
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_SIZE && controller) {
        RECT bounds{};
        GetClientRect(hwnd, &bounds);
        controller->put_Bounds(bounds);
    } else if (message == WM_SIZE && statusHandle) {
        RECT bounds{};
        GetClientRect(hwnd, &bounds);
        MoveWindow(statusHandle, 24, 24, bounds.right - 48, bounds.bottom - 48, TRUE);
    } else if (message == WM_DESTROY) {
        PostQuitMessage(0);
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

void createWebView(const std::wstring &url, const std::wstring &title, const std::wstring &ownerTokenScript) {
    setStatus(L"Starting the embedded browser…");
    const HRESULT initialized = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, nullptr, nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [url, title, ownerTokenScript](HRESULT result, ICoreWebView2Environment *environment) -> HRESULT {
                if (FAILED(result) || !environment) {
                    setStatus(L"WebView2 could not start. Install the Microsoft Edge WebView2 Runtime.");
                    return result;
                }
                return environment->CreateCoreWebView2Controller(windowHandle,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [url, title, ownerTokenScript](HRESULT controllerResult, ICoreWebView2Controller *created) -> HRESULT {
                            if (FAILED(controllerResult) || !created) {
                                setStatus(L"AETHER could not create its WebView2 window.");
                                return controllerResult;
                            }

                            controller = created;
                            RECT bounds{};
                            GetClientRect(windowHandle, &bounds);
                            controller->put_Bounds(bounds);
                            if (FAILED(controller->get_CoreWebView2(&webView)) || !webView) {
                                setStatus(L"AETHER could not initialize its WebView2 view.");
                                return E_FAIL;
                            }

                            webView->add_NavigationStarting(
                                Callback<ICoreWebView2NavigationStartingEventHandler>(
                                    [](ICoreWebView2 *, ICoreWebView2NavigationStartingEventArgs *args) -> HRESULT {
                                        LPWSTR rawUri = nullptr;
                                        if (SUCCEEDED(args->get_Uri(&rawUri)) && rawUri) {
                                            const std::wstring uri(rawUri);
                                            CoTaskMemFree(rawUri);
                                            const bool internalScheme = uri.rfind(L"about:", 0) == 0
                                                || uri.rfind(L"data:", 0) == 0
                                                || uri.rfind(L"blob:", 0) == 0;
                                            if (!internalScheme && !isTrustedUri(uri)) {
                                                args->put_Cancel(TRUE);
                                                ShellExecuteW(windowHandle, L"open", uri.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
                                            }
                                        }
                                        return S_OK;
                                    }).Get(), nullptr);

                            SetWindowTextW(windowHandle, title.c_str());
                            ShowWindow(statusHandle, SW_HIDE);
                            if (ownerTokenScript.empty()) return webView->Navigate(url.c_str());
                            return webView->AddScriptToExecuteOnDocumentCreated(
                                ownerTokenScript.c_str(),
                                Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
                                    [url](HRESULT scriptResult, LPCWSTR) -> HRESULT {
                                        if (FAILED(scriptResult)) {
                                            setStatus(L"AETHER could not configure the OpenDots session.");
                                            return scriptResult;
                                        }
                                        return webView->Navigate(url.c_str());
                                    }).Get());
                        }).Get());
            }).Get());
    if (FAILED(initialized)) {
        setStatus(L"WebView2 initialization failed. Install the Microsoft Edge WebView2 Runtime.");
    }
}
}

extern "C" int AETHERWebView2Run(
    const char *urlText,
    const char *titleText,
    const char *ownerTokenScriptText,
    const char *failureMessageText
) {
    const HRESULT apartment = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(apartment) && apartment != RPC_E_CHANGED_MODE) return static_cast<int>(apartment);

    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW windowClass{};
    windowClass.lpfnWndProc = WindowProc;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = L"AETHERWebView2Window";
    windowClass.hCursor = LoadCursor(nullptr, IDC_ARROW);
    if (!RegisterClassW(&windowClass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        CoUninitialize();
        return static_cast<int>(GetLastError());
    }

    windowHandle = CreateWindowExW(0, windowClass.lpszClassName, L"AETHER",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 1280, 840,
        nullptr, nullptr, instance, nullptr);
    if (!windowHandle) {
        const auto error = GetLastError();
        CoUninitialize();
        return static_cast<int>(error);
    }

    statusHandle = CreateWindowExW(0, L"STATIC", L"Starting OpenDots…",
        WS_CHILD | WS_VISIBLE | SS_CENTER, 24, 24, 1200, 760,
        windowHandle, nullptr, instance, nullptr);
    ShowWindow(windowHandle, SW_SHOW);
    UpdateWindow(windowHandle);

    const auto url = widen(urlText);
    const auto title = widen(titleText);
    const auto ownerTokenScript = widen(ownerTokenScriptText);
    trustedOrigin = originFor(url);
    if (url.empty()) {
        setStatus(widen(failureMessageText));
    } else {
        createWebView(url, title.empty() ? L"AETHER" : title, ownerTokenScript);
    }

    MSG message{};
    int result = 0;
    while ((result = static_cast<int>(GetMessageW(&message, nullptr, 0, 0))) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    controller.Reset();
    webView.Reset();
    windowHandle = nullptr;
    statusHandle = nullptr;
    trustedOrigin.clear();
    if (apartment == S_OK || apartment == S_FALSE) CoUninitialize();
    return result < 0 ? static_cast<int>(GetLastError()) : static_cast<int>(message.wParam);
}
