/*
 * popup-grab-test - deterministic X11 popup/pointer-grab regression tool
 *
 * Opens a normal window with a "menu bar". Clicking the bar opens an
 * override-redirect popup and grabs the pointer (owner_events, confined
 * to the popup), the same pattern browser menus and context menus use.
 * Motion and button events are recorded; clicking every item exits 0.
 *
 * Run inside a nested server (Xephyr/Xsunaba) and interact with the
 * host mouse to verify that pointer-grab popups receive complete,
 * correctly positioned input.
 *
 * Build: make tools
 * Usage: tools/popup-grab-test [DISPLAY]
 *
 * Exit status: 0 = all items clicked, 1 = timeout/error.
 *
 * Released under the MIT License. See the LICENSE file at the top of
 * the project tree for copyright and license details.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#define ITEM_COUNT 5
#define ITEM_W 120
#define ITEM_H 28
#define POPUP_W (ITEM_W + 16)
#define POPUP_H (ITEM_COUNT * ITEM_H + 16)

static int item_clicked[ITEM_COUNT];

static void
draw_popup(Display * dpy, Window win, GC gc)
{
    int i;

    XSetForeground(dpy, gc, 0xffffff);
    XFillRectangle(dpy, win, gc, 0, 0, POPUP_W, POPUP_H);
    XSetForeground(dpy, gc, 0x000000);
    XDrawRectangle(dpy, win, gc, 0, 0, POPUP_W - 1, POPUP_H - 1);
    for (i = 0; i < ITEM_COUNT; i++) {
        int y = 8 + i * ITEM_H;
        char label[32];

        XSetForeground(dpy, gc, item_clicked[i] ? 0x00aa00 : 0xdddddd);
        XFillRectangle(dpy, win, gc, 8, y, ITEM_W, ITEM_H - 4);
        XSetForeground(dpy, gc, 0x000000);
        XDrawRectangle(dpy, win, gc, 8, y, ITEM_W, ITEM_H - 4);
        snprintf(label, sizeof label, "item %d", i + 1);
        XDrawString(dpy, win, gc, 16, y + ITEM_H - 10,
                    label, (int) strlen(label));
    }
}

static int
all_clicked(void)
{
    int i;

    for (i = 0; i < ITEM_COUNT; i++)
        if (!item_clicked[i])
            return 0;
    return 1;
}

int
main(int argc, char **argv)
{
    Display *dpy;
    int screen;
    Window win;
    Window popup = None;
    GC gc;
    XEvent ev;
    time_t deadline;
    int done = 0;
    int rc = 1;

    dpy = XOpenDisplay(argc > 1 ? argv[1] : NULL);
    if (dpy == NULL) {
        fprintf(stderr, "popup-grab-test: cannot open display\n");
        return 1;
    }
    screen = DefaultScreen(dpy);
    win = XCreateSimpleWindow(dpy, RootWindow(dpy, screen),
                              0, 0, 640, 480, 0,
                              BlackPixel(dpy, screen),
                              WhitePixel(dpy, screen));
    XStoreName(dpy, win, "popup-grab-test");
    gc = XCreateGC(dpy, win, 0, NULL);
    XSelectInput(dpy, win,
                 ExposureMask | ButtonPressMask | StructureNotifyMask |
                 KeyPressMask);
    XMapWindow(dpy, win);

    printf("popup-grab-test: click the menu bar (top 40 rows),\n"
           "then click every popup item. Escape or 45 s quits.\n");
    fflush(stdout);
    deadline = time(NULL) + 45;

    while (!done) {
        time_t now = time(NULL);

        if (now >= deadline) {
            fprintf(stderr, "popup-grab-test: timeout\n");
            break;
        }
        if (XPending(dpy) == 0) {
            struct timeval tv = { 0, 50000 };

            select(0, NULL, NULL, NULL, &tv);
            continue;
        }
        XNextEvent(dpy, &ev);

        switch (ev.type) {
        case ConfigureNotify:
            printf("configure: %dx%d\n",
                   ev.xconfigure.width, ev.xconfigure.height);
            fflush(stdout);
            break;
        case Expose:
            if (ev.xexpose.count == 0) {
                XSetForeground(dpy, gc, 0xbbbbbb);
                XFillRectangle(dpy, win, gc, 0, 0, 640, 40);
                XSetForeground(dpy, gc, 0x000000);
                XDrawString(dpy, win, gc, 16, 26,
                            "menu (click here)", 17);
            }
            break;
        case ButtonPress:
            if (ev.xbutton.button != 1)
                break;
            if (popup == None && ev.xbutton.y < 40) {
                int x = ev.xbutton.x - 8;
                int y = 40;

                if (x + POPUP_W > 640)
                    x = 640 - POPUP_W;
                popup = XCreateSimpleWindow(dpy, win, x, y,
                                            POPUP_W, POPUP_H, 0,
                                            BlackPixel(dpy, screen),
                                            WhitePixel(dpy, screen));
                XSetWindowAttributes attrs;
                XEvent sev;

                attrs.override_redirect = True;
                XChangeWindowAttributes(dpy, popup, CWOverrideRedirect,
                                        &attrs);
                XSelectInput(dpy, popup,
                             ExposureMask | ButtonPressMask |
                             ButtonReleaseMask | PointerMotionMask |
                             KeyPressMask | StructureNotifyMask);
                XMapRaised(dpy, popup);
                XSync(dpy, False);
                draw_popup(dpy, popup, gc);
                if (XGrabPointer(dpy, popup, True,
                                 ButtonPressMask | ButtonReleaseMask |
                                 PointerMotionMask,
                                 GrabModeAsync, GrabModeAsync,
                                 popup, None, CurrentTime)
                    != GrabSuccess) {
                    fprintf(stderr,
                            "popup-grab-test: XGrabPointer failed\n");
                    goto out;
                }
                printf("popup opened at %d,%d; pointer grabbed\n",
                       x, y);
                fflush(stdout);
                /* swallow the grab's synthetic enter event */
                XWindowEvent(dpy, popup, EnterWindowMask, &sev);
            }
            break;
        case MotionNotify:
            if (popup != None && ev.xmotion.window == popup) {
                printf("motion in popup: %d,%d\n",
                       ev.xmotion.x, ev.xmotion.y);
                fflush(stdout);
            }
            break;
        case ButtonRelease:
            if (popup != None && ev.xbutton.window == popup) {
                int i = (ev.xbutton.y - 8) / ITEM_H;

                printf("release at %d,%d -> ",
                       ev.xbutton.x, ev.xbutton.y);
                if (i >= 0 && i < ITEM_COUNT) {
                    item_clicked[i] = 1;
                    printf("item %d clicked\n", i + 1);
                    draw_popup(dpy, popup, gc);
                }
                else {
                    printf("no item\n");
                }
                fflush(stdout);
                if (all_clicked()) {
                    printf("popup-grab-test: all items clicked\n");
                    done = 1;
                    rc = 0;
                }
            }
            break;
        case KeyPress:
            if (ev.xkey.window == win || ev.xkey.window == popup) {
                printf("popup-grab-test: abort\n");
                goto out;
            }
            break;
        case DestroyNotify:
            done = 1;
            break;
        }
    }

  out:
    if (popup != None)
        XUngrabPointer(dpy, CurrentTime);
    printf("summary: clicked %d/%d items\n",
           item_clicked[0] + item_clicked[1] + item_clicked[2] +
           item_clicked[3] + item_clicked[4],
           ITEM_COUNT);
    if (popup != None)
        XDestroyWindow(dpy, popup);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    return rc;
}
