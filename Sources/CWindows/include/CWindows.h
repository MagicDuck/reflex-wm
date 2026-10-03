#pragma once
#include <stdint.h>

typedef struct RWEvent {
  int kind; /* 0: none, 1: hotkey, 2: reload, 3: open config, 4: quit */
  int identifier;
} RWEvent;

int rw_app_start(const char *tooltip);
RWEvent rw_app_poll(int timeout_ms);
void rw_app_stop(void);
void rw_app_status(const char *text);
void rw_app_notify(const char *title, const char *body);
void rw_open_path(const char *path);

int rw_key_code(const char *name);
int rw_hotkey_register(int identifier, unsigned int modifiers, int key);
void rw_hotkey_unregister(int identifier);
unsigned long rw_last_error(void);

char *rw_snapshot_json(void);
void rw_free(void *memory);
int rw_window_rect(const char *id, int *x, int *y, int *width, int *height);
int rw_window_focus(const char *id);
int rw_window_close(const char *id);
int rw_window_set_rect(const char *id, int x, int y, int width, int height);
int rw_window_minimize(const char *id);
int rw_monitor_count(void);
int rw_monitor_rect(int index, int *x, int *y, int *width, int *height);
int rw_launch_command(const char *command_line);
int rw_launch_app(const char *application);
