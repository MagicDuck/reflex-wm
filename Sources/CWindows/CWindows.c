#define UNICODE
#define _UNICODE

#include <windows.h>
#include <shellapi.h>
#include <commctrl.h>
#include <psapi.h>
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "CWindows.h"

static HWND app_window;
static NOTIFYICONDATAW tray_icon;
static const UINT tray_message = WM_APP + 17;
static const UINT_PTR tray_id = 1;
static HINSTANCE app_instance;
static wchar_t app_tooltip[128] = L"reflex-wm";
static wchar_t app_status[128] = L"Starting...";

static wchar_t *to_wide(const char *value) {
  if (!value) {
    return NULL;
  }
  int count = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
  if (!count) {
    return NULL;
  }
  wchar_t *result = (wchar_t *)calloc((size_t)count, sizeof(wchar_t));
  if (result) {
    MultiByteToWideChar(CP_UTF8, 0, value, -1, result, count);
  }
  return result;
}

static char *to_utf8(const wchar_t *value) {
  if (!value) {
    return _strdup("");
  }
  int count = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (!count) {
    return _strdup("");
  }
  char *result = (char *)calloc((size_t)count, 1);
  if (result) {
    WideCharToMultiByte(CP_UTF8, 0, value, -1, result, count, NULL, NULL);
  }
  return result;
}

static LRESULT CALLBACK app_window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_HOTKEY) {
    return 0;
  }

  if (message == tray_message) {
    if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      HMENU menu = CreatePopupMenu();
      if (menu) {
        AppendMenuW(menu, MF_STRING | MF_GRAYED, 10, app_status);
        AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
        AppendMenuW(menu, MF_STRING, 11, L"Reload configuration");
        AppendMenuW(menu, MF_STRING, 12, L"Open configuration");
        AppendMenuW(menu, MF_STRING, 13, L"Quit reflex-wm");
        POINT point;
        GetCursorPos(&point);
        SetForegroundWindow(hwnd);
        TrackPopupMenu(
            menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, point.x, point.y, 0, hwnd, NULL);
        DestroyMenu(menu);
      }
    }
    return 0;
  }

  if (message == WM_COMMAND) {
    PostMessageW(hwnd, WM_APP + 30, LOWORD(wparam), 0);
    return 0;
  }

  if (message == WM_CLOSE) {
    DestroyWindow(hwnd);
    return 0;
  }
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

int rw_app_start(const char *tooltip) {
  app_instance = GetModuleHandleW(NULL);
  wchar_t *wide = to_wide(tooltip);
  if (wide) {
    wcsncpy_s(app_tooltip, 128, wide, _TRUNCATE);
    free(wide);
  }
  const wchar_t *class_name = L"ReflexWM.HiddenWindow";
  WNDCLASSW cls = {0};
  cls.lpfnWndProc = app_window_proc;
  cls.hInstance = app_instance;
  cls.lpszClassName = class_name;
  RegisterClassW(&cls);
  app_window = CreateWindowExW(0, class_name, L"reflex-wm", 0, 0, 0, 0, 0,
                               HWND_MESSAGE, NULL, app_instance, NULL);
  if (!app_window) {
    return 0;
  }
  memset(&tray_icon, 0, sizeof(tray_icon));
  tray_icon.cbSize = sizeof(tray_icon);
  tray_icon.hWnd = app_window;
  tray_icon.uID = tray_id;
  tray_icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon.uCallbackMessage = tray_message;
  tray_icon.hIcon = LoadIconW(NULL, IDI_APPLICATION);
  wcsncpy_s(tray_icon.szTip, ARRAYSIZE(tray_icon.szTip), app_tooltip, _TRUNCATE);
  if (!Shell_NotifyIconW(NIM_ADD, &tray_icon)) {
    DestroyWindow(app_window);
    app_window = NULL;
    return 0;
  }
  return 1;
}

RWEvent rw_app_poll(int timeout_ms) {
  RWEvent event = {0, 0};
  if (!app_window) {
    return event;
  }
  DWORD until = GetTickCount() + (DWORD)(timeout_ms < 0 ? 0 : timeout_ms);
  MSG message;
  do {
    while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        event.kind = 4;
        return event;
      }
      if (message.message == WM_HOTKEY) {
        event.kind = 1;
        event.identifier = (int)message.wParam;
        return event;
      }
      if (message.message == WM_APP + 30) {
        switch (message.wParam) {
          case 11:
            event.kind = 2;
            break;
          case 12:
            event.kind = 3;
            break;
          case 13:
            event.kind = 4;
            break;
        }
        if (event.kind) {
          return event;
        }
      }
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    if (timeout_ms == 0 || GetTickCount() >= until) break;
    MsgWaitForMultipleObjects(0, NULL, FALSE, 20, QS_ALLINPUT);
  } while (1);
  return event;
}

void rw_app_stop(void) {
  if (app_window) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon);
    DestroyWindow(app_window);
    app_window = NULL;
  }
}

void rw_app_status(const char *text) {
  wchar_t *wide = to_wide(text);
  if (!wide) {
    return;
  }
  wcsncpy_s(app_status, ARRAYSIZE(app_status), wide, _TRUNCATE);
  wcsncpy_s(tray_icon.szTip, ARRAYSIZE(tray_icon.szTip), wide, _TRUNCATE);
  tray_icon.uFlags = NIF_TIP;
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon);
  free(wide);
}

void rw_app_notify(const char *title, const char *body) {
  wchar_t *wtitle = to_wide(title);
  wchar_t *wbody = to_wide(body);
  if (!wtitle || !wbody) {
    free(wtitle);
    free(wbody);
    return;
  }
  tray_icon.uFlags = NIF_INFO;
  tray_icon.dwInfoFlags = NIIF_INFO;
  tray_icon.uTimeout = 8000;
  wcsncpy_s(tray_icon.szInfoTitle, ARRAYSIZE(tray_icon.szInfoTitle), wtitle, _TRUNCATE);
  wcsncpy_s(tray_icon.szInfo, ARRAYSIZE(tray_icon.szInfo), wbody, _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon);
  free(wtitle);
  free(wbody);
}

void rw_open_path(const char *path) {
  wchar_t *wide = to_wide(path);
  if (wide) {
    ShellExecuteW(NULL, L"open", wide, NULL, NULL, SW_SHOWNORMAL);
    free(wide);
  }
}

int rw_key_code(const char *name) {
  if (!name) {
    return 0;
  }
  if (strlen(name) == 1) {
    char c = (char)toupper((unsigned char)name[0]);
    if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
      return (int)c;
    }

    const char *punct = "`-=[]\\;'.,/";
    const int codes[] = {0xC0, 0xBD, 0xBB, 0xDB, 0xDD, 0xDC, 0xDE, 0xBC, 0xBE, 0xBF};
    const char *p = strchr(punct, name[0]);
    if (p) {
      return codes[p - punct];
    }
  }

  if (name[0] == 'f' && name[1]) {
    int n = atoi(name + 1);
    if (n >= 1 && n <= 20) {
      return VK_F1 + n - 1;
    }
  }

  struct Pair {
    const char *name;
    int code;
  } pairs[] = {
      {"return", VK_RETURN}, {"tab", VK_TAB},       {"space", VK_SPACE},
      {"escape", VK_ESCAPE}, {"delete", VK_DELETE}, {"home", VK_HOME},
      {"end", VK_END},       {"pageup", VK_PRIOR},  {"pagedown", VK_NEXT},
      {"left", VK_LEFT},     {"right", VK_RIGHT},   {"up", VK_UP},
      {"down", VK_DOWN},     {"printscr", VK_SNAPSHOT},
      {NULL, 0},
  };
  for (int i = 0; pairs[i].name; i++) {
    if (_stricmp(name, pairs[i].name) == 0) {
      return pairs[i].code;
    }
  }
  return 0;
}

int rw_hotkey_register(int identifier, unsigned int modifiers, int key) {
  return RegisterHotKey(app_window, identifier, modifiers | MOD_NOREPEAT, (UINT)key) != 0;
}

void rw_hotkey_unregister(int identifier) {
  UnregisterHotKey(app_window, identifier);
}

unsigned long rw_last_error(void) {
  return GetLastError();
}

static char *json_escape(const char *s) {
  size_t n = 3;
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    n += (*p == '"' || *p == '\\') ? 2 : (*p < 32 ? 6 : 1);
  }

  char *o = (char *)malloc(n);
  char *q = o;
  if (!o) {
    return NULL;
  }
  *q++ = '"';

  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    if (*p == '"' || *p == '\\') {
      *q++ = '\\';
      *q++ = *p;
    } else if (*p < 32) {
      sprintf(q, "\\u%04x", *p);
      q += 6;
    } else {
      *q++ = *p;
    }
  }

  *q++ = '"';
  *q = 0;
  return o;
}
typedef struct Snap {
  char *data;
  size_t length;
  size_t capacity;
  int first;
  char focused[32];
} Snap;

static BOOL CALLBACK add_window(HWND hwnd, LPARAM arg) {
  Snap *s = (Snap *)arg;
  if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER)) {
    return TRUE;
  }

  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (!pid || pid == GetCurrentProcessId()) {
    return TRUE;
  }

  wchar_t title_w[1024] = {0};
  wchar_t path_w[32768] = {0};
  GetWindowTextW(hwnd, title_w, 1024);
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process) {
    DWORD size = 32768;
    QueryFullProcessImageNameW(process, 0, path_w, &size);
    CloseHandle(process);
  }
  if (!path_w[0]) {
    return TRUE;
  }
  char *title = to_utf8(title_w);
  char *path = to_utf8(path_w);
  wchar_t *base = wcsrchr(path_w, L'\\');
  char *exe = to_utf8(base ? base + 1 : path_w);
  char *qt = json_escape(title);
  char *qp = json_escape(path);
  char *qe = json_escape(exe);
  if (!qt || !qp || !qe) {
    free(title);
    free(path);
    free(exe);
    free(qt);
    free(qp);
    free(qe);
    return TRUE;
  }

  char id[32];
  snprintf(id, sizeof(id), "%llu", (unsigned long long)(uintptr_t)hwnd);
  char item[150000];
  snprintf(item, sizeof(item),
           "%s{\"id\":\"%s\",\"title\":%s,\"appID\":%s,\"appName\":%s,\"executableName\":%s,\"pid\":%lu}",
           s->first ? "" : ",", id, qt, qp, qe, qe, (unsigned long)pid);

  size_t need = strlen(item);
  if (s->length + need + 1 > s->capacity) {
    size_t cap = s->capacity ? s->capacity * 2 : 4096;
    while (cap < s->length + need + 1) cap *= 2;
    char *p = (char *)realloc(s->data, cap);
    if (!p) goto done;
    s->data = p;
    s->capacity = cap;
  }

  memcpy(s->data + s->length, item, need);
  s->length += need;
  s->data[s->length] = 0;
  s->first = 0;
  if (hwnd == GetForegroundWindow()) {
    strncpy_s(s->focused, sizeof(s->focused), id, _TRUNCATE);
  }

done:
  free(title);
  free(path);
  free(exe);
  free(qt);
  free(qp);
  free(qe);
  return TRUE;
}
char *rw_snapshot_json(void) {
  Snap s = {0};
  s.first = 1;
  EnumWindows(add_window, (LPARAM)&s);
  if (!s.data) {
    s.data = (char *)calloc(1, 1);
  }

  size_t total = s.length + 128;
  char *result = (char *)malloc(total);
  if (!result) {
    free(s.data);
    return NULL;
  }

  char focused[64];
  if (s.focused[0]) {
    snprintf(focused, sizeof(focused), "\"%s\"", s.focused);
  } else {
    strcpy(focused, "null");
  }

  snprintf(result, total, "{\"focused\":%s,\"windows\":[%s]}", focused,
           s.data ? s.data : "");
  free(s.data);
  return result;
}

void rw_free(void *memory) {
  free(memory);
}

static HWND window_from_id(const char *id) {
  return (HWND)(uintptr_t)_strtoui64(id ? id : "0", NULL, 10);
}

int rw_window_rect(const char *id, int *x, int *y, int *w, int *h) {
  RECT rect;
  if (!GetWindowRect(window_from_id(id), &rect)) {
    return 0;
  }
  *x = rect.left;
  *y = rect.top;
  *w = rect.right - rect.left;
  *h = rect.bottom - rect.top;
  return 1;
}

int rw_window_focus(const char *id) {
  HWND hwnd = window_from_id(id);
  if (!IsWindow(hwnd)) {
    return 0;
  }
  ShowWindow(hwnd, SW_RESTORE);
  BringWindowToTop(hwnd);
  return SetForegroundWindow(hwnd) != 0;
}

int rw_window_close(const char *id) {
  HWND hwnd = window_from_id(id);
  return IsWindow(hwnd) && PostMessageW(hwnd, WM_CLOSE, 0, 0);
}

int rw_window_set_rect(const char *id, int x, int y, int w, int h) {
  return SetWindowPos(window_from_id(id), NULL, x, y, w, h,
                      SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW) != 0;
}

int rw_window_minimize(const char *id) {
  HWND hwnd = window_from_id(id);
  return IsWindow(hwnd) && ShowWindow(hwnd, SW_MINIMIZE);
}

typedef struct Monitors {
  RECT rects[64];
  int count;
} Monitors;

static BOOL CALLBACK add_monitor(HMONITOR monitor, HDC dc, LPRECT rect, LPARAM arg) {
  Monitors *monitors = (Monitors *)arg;
  if (monitors->count < 64) {
    MONITORINFO info = {.cbSize = sizeof(info)};
    if (GetMonitorInfoW(monitor, &info)) {
      monitors->rects[monitors->count++] = info.rcWork;
    }
  }
  return TRUE;
}

static void monitors_sort(Monitors *monitors) {
  memset(monitors, 0, sizeof(*monitors));
  EnumDisplayMonitors(NULL, NULL, add_monitor, (LPARAM)monitors);
  for (int i = 0; i < monitors->count; i++) {
    for (int j = i + 1; j < monitors->count; j++) {
      RECT *left = &monitors->rects[i];
      RECT *right = &monitors->rects[j];
      if (right->left < left->left || (right->left == left->left && right->top < left->top)) {
        RECT temp = *left;
        *left = *right;
        *right = temp;
      }
    }
  }
}

int rw_monitor_count(void) {
  Monitors monitors;
  monitors_sort(&monitors);
  return monitors.count;
}

int rw_monitor_rect(int index, int *x, int *y, int *w, int *h) {
  Monitors monitors;
  monitors_sort(&monitors);
  if (index < 0 || index >= monitors.count) {
    return 0;
  }

  RECT rect = monitors.rects[index];
  *x = rect.left;
  *y = rect.top;
  *w = rect.right - rect.left;
  *h = rect.bottom - rect.top;
  return 1;
}

int rw_launch_command(const char *line) {
  wchar_t *command_line = to_wide(line);
  if (!command_line) {
    return 0;
  }

  STARTUPINFOW startup_info = {.cb = sizeof(startup_info)};
  PROCESS_INFORMATION process_info = {0};
  BOOL success = CreateProcessW(NULL, command_line, NULL, NULL, FALSE,
                                CREATE_UNICODE_ENVIRONMENT, NULL, NULL,
                                &startup_info, &process_info);
  if (success) {
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
  }
  free(command_line);
  return success != 0;
}

int rw_launch_app(const char *application) {
  wchar_t *wide_application = to_wide(application);
  if (!wide_application) {
    return 0;
  }

  HINSTANCE result = ShellExecuteW(NULL, L"open", wide_application, NULL, NULL,
                                   SW_SHOWNORMAL);
  free(wide_application);
  return (INT_PTR)result > 32;
}
