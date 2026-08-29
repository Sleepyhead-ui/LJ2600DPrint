package io.github.sleepyhead.lj2600d.bootstrap;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.Date;
import org.osgi.framework.BundleActivator;
import org.osgi.framework.BundleContext;

public final class Activator implements BundleActivator {
    private static final String GATEWAY = "192.168.1.1";
    private static final File DISABLED = new File("/osgi/.lj2600d-bootstrap-disabled");
    private static final File LOG = new File("/osgi/lj2600d-print/osgi-bootstrap.log");
    private static final File WEB_WATCH = new File("/osgi/lj2600d-web/watch-web.sh");
    private volatile boolean stopping;
    private Thread worker;

    public void start(BundleContext context) {
        stopping = false;
        worker = new Thread(new Runnable() {
            public void run() {
                recover();
            }
        }, "lj2600d-bootstrap");
        worker.setDaemon(true);
        worker.start();
    }

    public void stop(BundleContext context) {
        stopping = true;
        if (worker != null) {
            worker.interrupt();
        }
    }

    private void recover() {
        if (DISABLED.exists()) {
            log("bootstrap disabled");
            return;
        }
        boolean telnetRequested = false;
        try {
            if (waitForServices(1, 1)) {
                log("services already online");
                return;
            }
            String mac = readMac();
            for (int attempt = 1; attempt <= 60 && !stopping; attempt++) {
                try {
                    telnetRequested = true;
                    httpTelnet(true, mac);
                    waitForPort(23, 10);
                    startAsRoot(mac);
                    httpTelnet(false, mac);
                    telnetRequested = false;
                    if (!waitForServices(30, 1)) {
                        throw new IOException("configured print services did not become ready");
                    }
                    log("print services recovered");
                    return;
                } catch (IOException failure) {
                    if (telnetRequested) {
                        try {
                            httpTelnet(false, mac);
                            telnetRequested = false;
                        } catch (IOException ignored) {
                        }
                    }
                    if (attempt == 60) {
                        throw failure;
                    }
                    sleep(5000L);
                }
            }
        } catch (Exception failure) {
            log("recovery failed: " + failure.getClass().getSimpleName() + ": " + safeMessage(failure));
        } finally {
            if (telnetRequested) {
                try {
                    httpTelnet(false, readMac());
                    log("temporary telnet closed");
                } catch (Exception failure) {
                    log("telnet close failed: " + failure.getClass().getSimpleName());
                }
            }
        }
    }

    private static String readMac() throws IOException {
        BufferedReader reader = new BufferedReader(new FileReader("/sys/class/net/br0/address"));
        try {
            String value = reader.readLine();
            if (value == null) {
                throw new IOException("gateway MAC is unavailable");
            }
            value = value.replace(":", "").replace("-", "").trim().toUpperCase();
            if (value.length() != 12) {
                throw new IOException("gateway MAC has an unexpected format");
            }
            return value;
        } finally {
            reader.close();
        }
    }

    private static void httpTelnet(boolean enabled, String mac) throws IOException {
        String flag = enabled ? "1" : "0";
        Socket socket = connect(80, 4000);
        try {
            OutputStream output = socket.getOutputStream();
            writeAscii(output, "GET /cgi-bin/telnetenable.cgi?telnetenable=" + flag + "&key=" + mac
                + " HTTP/1.0\r\nHost: " + GATEWAY + "\r\nConnection: close\r\n\r\n");
            String response = readToEnd(socket.getInputStream(), 65536);
            if (response.indexOf(" 200 ") < 0 || response.toLowerCase().indexOf("telnet") < 0) {
                throw new IOException("gateway rejected telnet control request");
            }
        } finally {
            socket.close();
        }
    }

    private static void startAsRoot(String mac) throws IOException {
        Socket socket = connect(23, 5000);
        socket.setSoTimeout(7000);
        try {
            InputStream input = socket.getInputStream();
            OutputStream output = socket.getOutputStream();
            readUntil(input, "login:", 32768);
            writeAscii(output, "admin\r\n");
            readUntil(input, "password:", 32768);
            writeAscii(output, "Fh@" + mac.substring(6) + "\r\n");
            String login = readUntil(input, "#", 65536);
            if (login.toLowerCase().indexOf("login incorrect") >= 0) {
                throw new IOException("gateway login failed");
            }
            String command = "if ! ps | grep '[o]sgi/lj2600d-print/watch.sh' >/dev/null; then "
                + "rm -f /var/tmp/lj2600d-watch.pid; "
                + "nohup /fhconf/lj2600d-start.sh >/var/tmp/lj2600d-watch.launch.log 2>&1 & fi";
            writeAscii(output, command + "\r\n");
            sleep(800L);
            writeAscii(output, "exit\r\n");
        } finally {
            socket.close();
        }
    }

    private boolean waitForServices(int attempts, int delaySeconds) {
        for (int i = 0; i < attempts && !stopping; i++) {
            if (portOpen(515, 1000) && (!WEB_WATCH.isFile() || portOpen(8631, 1000))) {
                return true;
            }
            sleep(delaySeconds * 1000L);
        }
        return false;
    }

    private void waitForPort(int port, int attempts) throws IOException {
        for (int i = 0; i < attempts && !stopping; i++) {
            if (portOpen(port, 1000)) {
                return;
            }
            sleep(1000L);
        }
        throw new IOException("telnet port did not open");
    }

    private static boolean portOpen(int port, int timeoutMillis) {
        Socket socket = new Socket();
        try {
            socket.connect(new InetSocketAddress(GATEWAY, port), timeoutMillis);
            return true;
        } catch (IOException ignored) {
            return false;
        } finally {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static Socket connect(int port, int timeoutMillis) throws IOException {
        Socket socket = new Socket();
        socket.connect(new InetSocketAddress(GATEWAY, port), timeoutMillis);
        socket.setSoTimeout(timeoutMillis);
        return socket;
    }

    private static String readUntil(InputStream input, String token, int limit) throws IOException {
        StringBuilder text = new StringBuilder();
        String expected = token.toLowerCase();
        while (text.length() < limit) {
            int value = input.read();
            if (value < 0) {
                break;
            }
            if (value == 255) {
                input.read();
                input.read();
                continue;
            }
            if (value == 0 || value == 13) {
                continue;
            }
            text.append((char) value);
            String current = text.toString().toLowerCase();
            if (current.indexOf(expected) >= 0 || current.indexOf("login incorrect") >= 0) {
                return text.toString();
            }
        }
        throw new IOException("telnet prompt was not received");
    }

    private static String readToEnd(InputStream input, int limit) throws IOException {
        StringBuilder text = new StringBuilder();
        while (text.length() < limit) {
            int value = input.read();
            if (value < 0) {
                break;
            }
            text.append((char) value);
        }
        return text.toString();
    }

    private static void writeAscii(OutputStream output, String value) throws IOException {
        output.write(value.getBytes("US-ASCII"));
        output.flush();
    }

    private static void sleep(long milliseconds) {
        try {
            Thread.sleep(milliseconds);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    private static String safeMessage(Exception failure) {
        String message = failure.getMessage();
        return message == null ? "no detail" : message.replace('\r', ' ').replace('\n', ' ');
    }

    private static synchronized void log(String message) {
        FileWriter writer = null;
        try {
            writer = new FileWriter(LOG, true);
            writer.write(new Date().toString());
            writer.write(" ");
            writer.write(message);
            writer.write("\n");
        } catch (IOException ignored) {
        } finally {
            if (writer != null) {
                try {
                    writer.close();
                } catch (IOException ignored) {
                }
            }
        }
    }
}
