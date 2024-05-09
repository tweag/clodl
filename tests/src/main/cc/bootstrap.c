#include <HsFFI.h>
#include <Rts.h>
#include <jni.h>
#include <setjmp.h>
#include <stdlib.h>  // For malloc, free
#include <string.h>  // For strdup

/* mainEntryPoint() is provided by the Haskell side and it is only
 * needed what main needs to be invoked. We want this code to still
 * be loadable without mainEntryPoint if we don't need to invoke it.
 *
 * Because of this we make mainEntryPoint a weak symbol. The nm(1) man page
 * says:
 *
 * > When a weak undefined symbol is linked and the symbol is not
 * > defined, the value of the symbol is determined in
 * > a system-specific manner without error.
 *
 * See also: https://gcc.gnu.org/onlinedocs/gcc/Common-Function-Attributes.html#index-g_t_0040code_007bweak_007d-function-attribute-3369
 */
extern int mainEntryPoint() __attribute__((weak));

static int init_argv(JNIEnv *env, jstring appName, jobjectArray args, int *argc, char **argv[])
{
	int rc = 0;

	(*env)->PushLocalFrame(env, 0);

	if (args)
		*argc = (*env)->GetArrayLength(env, args);
	else
		*argc = 0;

	if ((*env)->ExceptionOccurred(env))
		return -1;

	/* Allocate enough memory for argv[0] and terminating null. */
	*argv = malloc((*argc + 2) * sizeof(char *));
	const char *app_name = (*env)->GetStringUTFChars(env, appName, NULL);
	if (!app_name || !((*argv)[0] = strdup(app_name)))
		rc = -1;
	(*env)->ReleaseStringUTFChars(env, appName, app_name);
	(*argv)[*argc] = NULL;

	for (int i = 0; i < *argc; i++)
	{
		jstring jstr = (*env)->GetObjectArrayElement(env, args, i);
		const char *str = (*env)->GetStringUTFChars(env, jstr, NULL);
		if (!str || !((*argv)[i+1] = strdup(str)))
			rc = -1;
		(*env)->ReleaseStringUTFChars(env, jstr, str);
	}

	(*env)->PopLocalFrame(env, NULL);
	return rc;
}

static void fini_argv(int argc, char *argv[])
{
	for (int i = 0; i < argc; i++) {
		free(argv[i]);
	}
	free(argv);
}

JNIEXPORT void JNICALL Java_io_tweag_jarify_HaskellLibraryLoader_initializeHaskell
(JNIEnv *env, jclass klass, jstring appName, jobjectArray args)
{
	int argc;
	char **argv;

	init_argv(env, appName, args, &argc, &argv);
	hs_init_with_rtsopts(&argc, &argv);
	if (!rtsSupportsBoundThreads()) {
	  (*env)->FatalError(env,"Jarify.initializeHaskell: Haskell RTS is not threaded.");
  }
}

// Use the haskell main closure directly
extern StgClosure ZCMain_main_closure __attribute__((weak));

static jmp_buf bootstrap_env;

/* A global callback defined in the GHC RTS. */
extern void (*exitFn)(int);

static void bypass_exit(int rc)
{
	/* If the exit code is 0, then jump the control flow back to
	 * invokeMain(), because we don't want the RTS to call
	 * exit() - we'd like to give the JVM a chance to perform
	 * whatever cleanup it needs. */
	if(!rc) longjmp(bootstrap_env, 0);
}

JNIEXPORT void JNICALL Java_io_tweag_jarify_JarifyMain_invokeMain
(JNIEnv *env, jclass klass, jstring appName, jobjectArray args)
{
	int argc;
	char **argv;

	/* Set a control prompt just before calling main. If exitFn is
	 * called, just proceed with cleanup.
	 */
	exitFn = bypass_exit;
	if(setjmp(bootstrap_env)) goto cleanup;

	init_argv(env, appName, args, &argc, &argv);

	// Call the Haskell main() function.
    hs_init_with_rtsopts(&argc, &argv);

    mainEntryPoint();

    // Shutdown the RTS but do not terminate the process
    hs_exit();

cleanup:
	fini_argv(argc, argv);
}
