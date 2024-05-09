package io.tweag.jarify;

import io.tweag.jarify.HaskellLibraryLoader;

public class JarifyMain {
    private static native void invokeMain(String appName, String[] args);
    public static void main(String[] args) {
        HaskellLibraryLoader.loadLibraries();
        invokeMain("jarify-app", args);
    }
}
