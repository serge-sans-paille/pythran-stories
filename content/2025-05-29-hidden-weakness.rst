A Hidden Weakness
#################

:date: 2025-05-29
:category: mozilla
:lang: en
:authors: serge-sans-paille
:summary: A surprising combination of symbol qualifiers that lead to a long bug hunt.

This is the story of a bug hunt that lasted much longer than expected, but ended
with the dearest of all treasures: *knowledge*.

Let's draw some context: the Android platform defines different API levels.
Unsurprisingly, some symbols are only defined starting with a given API version.
For instance, ``ASystemFontIterator_open`` is only available starting at API 29.

Unconditionally trying to use ``ASystemFontIterator_open`` while targeting an
API older than 29 leads to a linker error (an undefined reference), which makes
sense because the symbol, well, does not exist at that API level.

So a native application that wants to use this symbol can either refuse to run on
older API, or use a combination of ``dlopen`` and ``dlsym`` to dynamically
lookup for the symbol and provide a fallback if it does not exist. The latter
approach is used on Fenix, the Android version of Firefox.

Introducing ``__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__``
========================================================

As an alternative to the features from ``<dlfcn.h>``, Android build system makes
it possible to define ``-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__``, combine it
with a compiler check through ``-Werror=unguarded-availability`` and a runtime
check through ``__builtin_available``. Here is an example:

.. code-block:: c

   // The header that defines ASystemFontIterator_open.
   #include <android/system_fonts.h>

   ...

   // Runtime check for API level
   if (__builtin_available(android 29, *)) {
       /* Reference to the actual symbol. Does not fail at link time because an
          alternative weak definition is always provided by <android/system_fonts.h>*/
       auto *iterator = ASystemFontIterator_open();
       ...
   }

There's a lot happening there, so let's dive in the wilderness of compiler
extensions.

``<android/system_fonts.h>``
----------------------------

``ASystemFontIterator_open`` is defined in ``<android/system_fonts.h>`` as:

.. code-block:: c

   ASystemFontIterator* _Nullable ASystemFontIterator_open() __INTRODUCED_IN(29);

The ``_Nullable`` attribute is an interesting topic, but it's a side quest we're
not going to explore today. The macro function ``__INTRODUCED_IN(...)`` is
defined in ``<android/versioning.h>`` as:

.. code-block:: c

   #define __INTRODUCED_IN(api_level) __BIONIC_AVAILABILITY(introduced=api_level)

And ``__BIONIC_AVAILABILITY`` is conditionally defined in the same header as:

.. code-block:: c

   #if defined(__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__)
     #define __BIONIC_AVAILABILITY(__what, ...) __attribute__((__availability__(android,__what __VA_OPT__(,) __VA_ARGS__)))
   #else
     #define __BIONIC_AVAILABILITY(__what, ...) __attribute__((__availability__(android,strict,__what __VA_OPT__(,) __VA_ARGS__)))
   #endif

So in our case ``ASystemFontIterator_open`` is flagged either with
``__attribute__((__availability__(android,introduced=29))`` or
``__attribute__((__availability__(android,strict,introduced=29))``.

Let's write a simple C code containing only the following:

.. code-block:: shell

   $ cat > a.c << EOF
   void foo(void) __attribute__((__availability__(android,introduced=29)));
   void bar(void) __attribute__((__availability__(android,strict,introduced=29)));
   void foobar(void) {
     foo();
     bar();
   }
   EOF

Compile and inspect it:

.. code-block:: shell

   $ clang --target=x86_64-linux-android21 -c a.c
   a.c:5:3: error: 'bar' is unavailable: introduced in Android 29 android
       5 |   bar();
         |   ^
   a.c:2:6: note: 'bar' has been explicitly marked unavailable here
       2 | void bar(void) __attribute__((__availability__(android,strict,introduced=29)));
         |      ^
   1 error generated.

ok, so the ``strict`` keyword implies a compilation error if we reference that
symbol while targeting a lower version. Good. Let's remove it:

.. code-block:: shell

   $ cat > b.c << EOF
   void foo(void) __attribute__((__availability__(android,introduced=29)));
   void foobar(void) {
     foo();
   }
   EOF
   $ clang --target=x86_64-linux-android21 -c b.c
   $ nm b.o
                    w foo
   0000000000000000 T foobar
   $ readelf -s b.o

   Symbol table '.symtab' contains 5 entries:
      Num:    Value          Size Type    Bind   Vis      Ndx Name
        0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND 
        1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS b.c
        2: 0000000000000000     0 SECTION LOCAL  DEFAULT    2 .text
        3: 0000000000000000    11 FUNC    GLOBAL DEFAULT    2 foobar
        4: 0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND foo

No compilation error, even though the symbol ``foo`` is marked as available only
for more recent API. Instead we end up with a symbol ``foo`` marked as ``WEAK``
(``w``) and ``UND`` (for undefined). Calling this symbol is equivalent to
dereferencing a ``nullptr`` and ends up with a segfault. Not super safe!

``-Werror=unguarded-availability``
----------------------------------

Fortunately, Clang provides a dedicated warning ``-Wungarded-availability``,
turned into an error through ``-Werror=unguarded-availability``. This flag
enables static checking for calls that would resolve into calling undefined weak
reference because of an ``__availability__`` mismatch.

Indeed in our case:

.. code-block:: shell

   $ clang --target=x86_64-linux-android21 -c b.c -Werror=unguarded-availability
   b.c:3:3: error: 'foo' is only available on Android 29 or newer [-Werror,-Wunguarded-availability]
       3 |   foo();
         |   ^~~
   b.c:1:6: note: 'foo' has been marked as being introduced in Android 29 here, but the deployment target is Android 21
       1 | void foo(void) __attribute__((__availability__(android,introduced=29)));
         |      ^
   b.c:3:3: note: enclose 'foo' in a __builtin_available check to silence this warning
       3 |   foo();
         |   ^~~   
   1 error generated.

Let's follow the compiler hint and guard our execution:

.. code-block:: shell

   $ cat > c.c << EOF
   void foo(void) __attribute__((__availability__(android,introduced=29)));
   void foobar(void) {
     if (__builtin_available(android 29, *))
       foo();
   }
   EOF
   $ clang --target=x86_64-linux-android21 -c c.c -Werror=unguarded-availability

No error, and indeed a guard is generated, as shown by the intermediate compiler
representation:

.. code-block:: shell

   $ clang --target=x86_64-linux-android21 -S -emit-llvm c.c -Werror=unguarded-availability
   ...
   define dso_local void @foobar() #0 {
     %1 = call i32 @__isOSVersionAtLeast(i32 29, i32 0, i32 0) #2
     %2 = icmp ne i32 %1, 0
     br i1 %2, label %3, label %4

   3:                                                ; preds = %0
     call void @foo()
     br label %4

   4:                                                ; preds = %3, %0
     ret void
   }

The function ``__isOSVersionAtLeast`` is part of the compiler runtime and its
implementation performs a costly check at first call, memoize the result and
then just reads the memoized result, which is quite fast.


The Actual Quest
================

This was a long detour before we reach our archenemy: the Firefox build system.
In a situation similar to the one described above, we indeed end up with a weak
symbol for ``ASystemFontIterator_open`` in the object file, but when creating a
shared library, the symbol is just marked as undefined, and on system with
recent API, the ``__isOSVersionAtLeast`` check passes but the guarded symbol is
undefined and everything went kaboom.

I'll spare you the detail I took to verify that the ``libandroid.so`` we use is
the right one, it has the right symbol which should supersedes the weak definition
of ``ASystemFontIterator_open`` if it were marked as weak, but because it's
marked undefined, it's just not there. Why would that happen?

Then I carefully compared the symbols between my object file from the Firefox
build system, and the one from my minimal reproducer above. And I ended up with
these two lines:

.. code::

   0000000000000000     0 NOTYPE  WEAK   HIDDEN   UND ASystemFontIterator_open

   0000000000000000     0 NOTYPE  WEAK   DEFAULT  UND foo

They look the same. But, wait, ``HIDDEN``? Why would,
``ASystemFontIterator_open``, a symbol that comes from a system header, be
marked as ``HIDDEN``? I quickly double-checked and there was no
``-fvisibility=hidden`` on the compiler invocation.

But there was something else.

A simple flag that looked innocent.

``-include config/gcc_hidden.h``

And in that very single file:

.. code-block:: sh

   $ cat config/gcc_hidden.h
   /* This Source Code Form is subject to the terms of the Mozilla Public
    * License, v. 2.0. If a copy of the MPL was not distributed with this
    * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

   /* Begin all files as hidden visibility */
   #pragma GCC visibility push(hidden)

*Et voilà*, Firefox defaults to building with hidden visibility, this impacts
the weak symbols generated as a consequence of ``__attribute__((__availability__(android,introduced=29)))`` and we can indeed reproduce the issue:

.. code-block:: sh

   $ cat > d.c << EOF
   #pragma GCC visibility push(hidden)
   void foo(void) __attribute__((__availability__(android,introduced=29)));
   void foobar(void) {
     foo();
   }
   EOF
   $ clang --target=x86_64-linux-android21 -c b.c
   $ readelf -s b.o | grep -E '\<foo\>'
   4: 0000000000000000     0 NOTYPE  WEAK   HIDDEN   UND foo
   $ clang -shared b.o -o libfoo.so
   $ nm libfoo.so | grep -E '\<foo\>'
   $ objdump -S libfoo.so
   ...
   0000000000000320 <foobar>:
    320:	55                   	push   %rbp
    321:	48 89 e5             	mov    %rsp,%rbp
    324:	e8 d7 fc ff ff       	call   0 <_init-0x224>
    329:	5d                   	pop    %rbp
    32a:	c3                   	ret
   ...

the call to ``foo`` got turned into a call to ``0``. Even on more recent
platforms, a ``0`` stays a ``0``, the weak reference trick no longer works.

The Fix
=======

As usual, the fix is very small, compared to the amount of work required to find
it. In our case we can temporarily change the default visibility when including
android system headers, as in:

.. code-block:: c

    #pragma GCC visibility push(default)
    #include <android/system_fonts.h>
    #pragma GCC visibility pop

As it's often the case, the journey is the real reward. But getting `Bug 1966309 <https://bugzilla.mozilla.org/show_bug.cgi?id=1966309>`_
fixed is also not bad ;-)


Acknowledgments
===============

Thanks goes to Olivia Hall for providing initial help with Android platform
details.
