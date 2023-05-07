How unity builds crept into the Firefox Build System
####################################################

:date: 2023-05-03
:category: mozilla
:lang: en
:authors: Serge Guelton
:original_url: how-unity-builds-lurked-into-the-firefox-build-system.html
:summary: Jumbo builds make C++ code compilation faster, but what happens when
          you require them?


Unity Build
===========

`Unity builds <https://en.wikipedia.org/wiki/Unity_build>`_, a.k.a. unified build or jumbo builds, is a technique that consists in
concatenating several C or C++ files in one before invoking the compiler. This generally
leads to faster compilation time in part because it aggregates the cost of parsing the
same headers over and over.

It is one of the many approach one can use to reduce C++ software compilation
time, alongside precompiled headers and C++20 modules.

It is not an obscure technique: it's officially supported by CMake through
``CMAKE_UNITY_BUILD`` (see
https://cmake.org/cmake/help/latest/variable/CMAKE_UNITY_BUILD.html).

At some point, the Chromium project supported doing jumbo builds:
https://chromium.googlesource.com/chromium/src.git/+/65.0.3283.0/docs/jumbo.md,
even if it got rid of it afterward
https://groups.google.com/a/chromium.org/g/chromium-dev/c/DP9TQszzQLI

It is also supported by the internal build system used at Mozilla. And the
speedup is there, a unified build (the default) runs twice as fast as an hybrid
build (``--disable-unified-build``) on my setup. As a side effect, in pre-LTO
area, this also led to better performance as it makes more information available
to the compiler.

Wait, did I write *hybrid build* and not *regular build*? As it turns out, under
``--disable-unified-build`` some parts of Firefox are still built in unified
mode, because they **require it**, probably for historical reason.

It's great to be able to do a unified build. It's not great to have a codebase
that does not compile unless you have a unity build: static analyzers are not
used to work on non-self contained sources (see https://github.com/clangd/clangd/issues/45), unity build implies a slight overhead during
incremental builds. What makes it worse is that developer start to rely on
unified build and get lazy in the way they develop.

Jumbo Build Creeps
==================

In the following we assume ``a.cpp`` and ``b.cpp`` are jumbo built as

.. code-block:: c++

   // jumbo.cpp
   #include "a.cpp"
   #include "b.cpp"

Let's have fun while collecting some of the cases found in the Firefox codebase
while removing the unify build requirement.


Skipping includes
-----------------

.. code-block:: c++

   // a.cpp
   #include <iostream>
   void foo() {
     std::cout << "hello" << std::endl;
   }

   // b.cpp
   void bar() {
     std::cout << "hello" << std::endl;
   }

Indeed, why including a header when another compilation unit that comes *before* you in
the unified build is including it?

Accessing static functions
--------------------------

.. code-block:: c++

   // a.cpp
   #include <iostream>
   static void foo() {
     std::cout << "hello" << std::endl;
   }

   // b.cpp
   void bar() {
     foo();
   }

Isn't that a good property to be able to access a function that's meant to be
private?

Trying to be smart with macro
-----------------------------

.. code-block:: c++

   // a.cpp
   #include <iostream>
   #define FOO 1

   // b.cpp
   #ifdef FOO
     #define BAR
   #endif

Defining a macro in one compilation unit and have it affect another compilation
unit has been a real nightmare.

Static templates
----------------

.. code-block:: c++

   // a.cpp
   #include <iostream>
   template <typename T>
   void foo(T const& arg) {
     std::cout << arg << std::endl;
   }

   // b.cpp
   #include <iostream>
   void bar(int i) {
     foo(i);
   }

Isn't it great when you don't need to put your template definition in the
header? Static visibility for templates ``:-)``.

Template specialization
-----------------------

.. code-block:: c++

   // foobar.h
   #ifndef FOOBAR_H
   #define FOOBAR_H
   #include <iostream>
   template <typename T>
   void foobar(T arg) {
     std::cout << arg << std::endl;
   }
   #endif

   // a.cpp
   #include "foobar.h"
   template <>
   void foobar<int>(int arg) {
     std::cout << "int: " << arg << std::endl;
   }

   // b.cpp
   #include "foobar.h"
   void bar(int i) {
     foobar(i);
   }

This one is terrible, because it doesn't give any compile time error, but a
runtime error ``:-/``.


Leaking using namespace
-----------------------

.. code-block:: c++

   // a.cpp
   #include <iostream>
   using namespace std;

   void foo() {
     cout << "hello" << std::endl;
   }

   // b.cpp
   #include <iostream>
   void bar() {
     cout << "hello" << std::endl;
   }

You can use symbols from namespace used from other compilation unit. That's
exactly the same problem as leaking macro or static definitions: it breaks the
compilation unit scope.

Putting function implementation in header
-----------------------------------------

.. code-block:: c++

   // foobar.h
   #ifndef FOOBAR_H
   #define FOOBAR_H
   #include <iostream>
   void foobar() {
     std::cout << "hello" << std::endl;
   }
   #endif

   // a.cpp
   #include "foobar.h"
   void foo() {
     foobar();
   }

   // b.cpp
   #include "foobar.h"
   void bar() {
     foobar();
   }

As each header is only included once, you can put your function definition in
your header. Easy!

Putting constant initializer in implementation
----------------------------------------------

.. code-block:: c++

   // foobar.h
   #ifndef FOOBAR_H
   #define FOOBAR_H
   struct foo {
   static const int VALUE;
   };
   #endif

   // a.cpp
   #include "foobar.h"
   const int foo::VALUE = 1;

   // b.cpp
   #include "foobar.h"
   static_assert(foo::VALUE == 1, "ok");

The constant expression lacks its initializer.

Error about functions without a valid declarations get silented
---------------------------------------------------------------


.. code-block:: c++

   // foobar.h
   #ifndef FOOBAR_H
   #define FOOBAR_H
   void foo(int * ptr);
   #endif

   // a.cpp
   #include "foobar.h"
   void foo(const int * ptr) {
   }

   // b.cpp
   #include "foobar.h"
   void bar(const int * ptr) {
       return foo(ptr);
   }

Invalid forward declaration but who cares, when the definition can be found and
the compiler doesn't warn about unused forward declaration?

Unexpected aspect: less warnings
--------------------------------

.. code-block:: c++

   // a.cpp
   static int foo = 0;

   // b.cpp
   #include "a.cpp"

Compiling ``a.cpp`` yields an unused warning, but not compiling ``b.cpp``. So
hybrid builds relying on ``#including`` multiple sources actually decrease the
warning level.

Headers without include guard
-----------------------------

.. code-block:: c++

   // foobar.h
   struct Foo {};

   // a.cpp
   #include "foobar.h"
   void a(Foo&) {}

   // b.cpp
   void b(Foo&) {}

Fixing the missing include for ``b.cpp`` leads to type redefinition because the header
is not guarded.


About the Firefox codebase
==========================

The removal of ``REQUIRES_UNIFIED_BUILD`` across the Firefox codebase was
tracked under https://bugzilla.mozilla.org/show_bug.cgi?id=1626530. Since I
focused on this, I've landed more than 150 commits, modifying more than 800
sources files. And it's now done, no more hard requirement of unified build,
back to a normal situation.

Was it worth the effort? Yes: it prevents bad coding practices, and static
analysis is now more useful compared to what it could do with unified builds.

And we're sure we won't regress as our CI now builds in both unified and non-unified mode!

Acknowledgments
---------------

Thanks to Paul Adenot for proof-reading this blog post and to Andi-Bogdan
Postelnicu for reviewing most of the commits mentioned above.
