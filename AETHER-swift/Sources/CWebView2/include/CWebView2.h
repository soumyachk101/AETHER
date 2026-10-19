#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int AETHERWebView2Run(
    const char *url,
    const char *title,
    const char *ownerTokenScript,
    const char *failureMessage
);

#ifdef __cplusplus
}
#endif
