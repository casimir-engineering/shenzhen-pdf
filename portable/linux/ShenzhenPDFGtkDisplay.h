#ifndef SHENZHENPDF_GTK_DISPLAY_H
#define SHENZHENPDF_GTK_DISPLAY_H

#include <glib.h>

typedef struct spdf_gtk_tab_title {
    const char* path;
    const char* title;
} spdf_gtk_tab_title;

char* spdf_gtk_display_name_for_path(const char* path);
char* spdf_gtk_display_label_without_extension(const char* label);
char* spdf_gtk_display_path_without_extension(const char* path);
char* spdf_gtk_disambiguated_tab_title(const spdf_gtk_tab_title* tabs, int count, int index);

#endif
