#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Canal nativo para leer/escribir imágenes del portapapeles vía GTK (sin
  // herramientas externas como wl-clipboard). Métodos "getImagePng" (leer) y
  // "setImagePng" (dejar una imagen recibida en el portapapeles).
  FlMethodChannel* clipboard_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Fija una imagen en el portapapeles un instante DESPUÉS de presentar la
// ventana. En Wayland, tomar posesión del portapapeles exige un "serial" de una
// interacción/foco reciente; si se hace sin foco, el compositor lo ignora en
// silencio y la imagen no queda pegable. Al diferirlo ~120 ms, el evento de foco
// que dispara gtk_window_present ya llegó. Libera el pixbuf al terminar.
static gboolean set_clipboard_image_deferred(gpointer data) {
  GdkPixbuf* pixbuf = GDK_PIXBUF(data);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_set_image(clipboard, pixbuf);
  g_object_unref(pixbuf);
  return G_SOURCE_REMOVE;
}

// Lee una imagen del portapapeles del sistema con GTK y la devuelve como bytes
// PNG (o null si no hay imagen). No depende de wl-clipboard ni de nada externo.
static void clipboard_method_call_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "getImagePng") == 0) {
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    GdkPixbuf* pixbuf = gtk_clipboard_wait_for_image(clipboard);
    if (pixbuf == nullptr) {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      gchar* buffer = nullptr;
      gsize buffer_size = 0;
      g_autoptr(GError) save_error = nullptr;
      gboolean ok = gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size,
                                              "png", &save_error, nullptr);
      g_object_unref(pixbuf);
      if (ok) {
        g_autoptr(FlValue) result =
            fl_value_new_uint8_list((const uint8_t*)buffer, buffer_size);
        g_free(buffer);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      } else {
        response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(fl_value_new_null()));
      }
    }
  } else if (strcmp(fl_method_call_get_name(method_call), "setImagePng") == 0) {
    // Recibe los bytes de una imagen (cualquier formato que GdkPixbuf entienda)
    // y la deja en el portapapeles del sistema como imagen. Devuelve true/false.
    FlValue* args = fl_method_call_get_args(method_call);
    gboolean done = FALSE;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_UINT8_LIST) {
      const uint8_t* data = fl_value_get_uint8_list(args);
      size_t len = fl_value_get_length(args);
      GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
      g_autoptr(GError) load_error = nullptr;
      gboolean ok = gdk_pixbuf_loader_write(loader, data, len, &load_error);
      // Cerrar siempre el loader (exactamente una vez) para no filtrarlo.
      gboolean closed = gdk_pixbuf_loader_close(loader, ok ? &load_error : nullptr);
      if (ok && closed) {
        GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
        if (pixbuf != nullptr) {
          // Presentar la caja de sbox un instante para tener foco/serial en
          // Wayland, y fijar la imagen justo después (diferido) — ver
          // set_clipboard_image_deferred. Sin foco, el set se ignora en Wayland.
          MyApplication* self = MY_APPLICATION(user_data);
          GList* windows = gtk_application_get_windows(GTK_APPLICATION(self));
          if (windows != nullptr) {
            gtk_window_present(GTK_WINDOW(windows->data));
          }
          g_object_ref(pixbuf);  // mantener vivo hasta el set diferido
          g_timeout_add(120, set_clipboard_image_deferred, pixbuf);
          done = TRUE;
        }
      }
      g_object_unref(loader);
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(done)));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("sbox clipboard: respuesta fallida: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Instancia única: si ya hay una ventana (segundo lanzamiento de sbox), traerla
  // al frente en vez de abrir otra caja. Evita dos hosts peleando por el puerto
  // 47718 (uno escucha con un código y el otro muestra otro → no conecta).
  GList* existing = gtk_application_get_windows(GTK_APPLICATION(application));
  if (existing != nullptr) {
    gtk_window_present(GTK_WINDOW(existing->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // sbox is a small, frameless, translucent floating box. We skip the GTK
  // header bar entirely (window_manager removes the window decorations from
  // Dart) and give the window an RGBA visual so it can be composited with a
  // real alpha channel (rounded translucent corners).
  gtk_window_set_title(window, "sbox");
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }

  gtk_window_set_default_size(window, 360, 440);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Transparent so the rounded translucent box drawn by Flutter shows through.
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Canal nativo de portapapeles (imágenes) — usa GTK, ya enlazado.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "sbox/clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->clipboard_channel, clipboard_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->clipboard_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Instancia única (antes NON_UNIQUE, que permitía dos cajas a la vez). Con los
  // flags por defecto, un segundo lanzamiento reenvía "activate" a la instancia
  // viva (ver my_application_activate) en vez de arrancar otro host.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_FLAGS_NONE, nullptr));
}
