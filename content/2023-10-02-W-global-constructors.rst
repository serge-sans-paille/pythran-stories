-Wglobal-constructors
#####################

:date: 2023-10-02-23
:category: mozilla
:lang: en
:authors: Serge Guelton
:summary: What's worse than a global variable? A global variable initialized at
          startup!


.. code-block:: c++

    #include <iostream>
    #include <unordered_set>
    #include <string>

    const std::unordered_set<std::string> primary_colors = {"red", "green", "blue"};

    int main(int argc, char const ** argv) {
        char const * color = argc > 1 ? argv[1] : "pink";
        return primary_colors.count(color) ? 0 : 1;
    }

Let's compile and run the snippet above:

.. code-block:: shell

   $ clang++ --version
   clang version 14.0.5 (Fedora 14.0.5-2.fc36)
   Target: x86_64-redhat-linux-gnu
   Thread model: posix
   InstalledDir: /usr/bin

   $ clang++ colors.cpp -O2 -o colors && ./colors green && echo ok
   ok

Let's be a bit more pedantic and turn all warnings on:


.. code-block:: shell

   $ clang++ colors.cpp -Wall -O2 -o colors && ./colors green && echo ok
   ok

No, I meant really pedantic (so that you don't waste your time trying:
``-pedantic`` doesn't find anything else)

.. code-block:: shell

   $ clang++ colors.cpp -Weverything -O2 -o colors && ./colors green && echo ok
    colors.cpp:5:56: warning: initialization of initializer_list object is incompatible with C++98 [-Wc++98-compat]
    const std::unordered_set<std::string> primary_colors = {"red", "green", "blue"};
                                                           ^~~~~~~~~~~~~~~~~~~~~~~~
    colors.cpp:5:39: warning: declaration requires an exit-time destructor [-Wexit-time-destructors]
    const std::unordered_set<std::string> primary_colors = {"red", "green", "blue"};
                                          ^
    colors.cpp:5:39: warning: declaration requires a global destructor [-Wglobal-constructors]
    3 warnings generated.
    ok


Now that's what I needed for my intro: ``-Wglobal-constructors`` (let's forget
about C++98, right?). ``-Wexit-time-destructors`` is a subset of
``-Wglobal-constructors``, so let's focus on global constructors.

Indeed we are creating a ``const`` unordered set named ``colors``, but the
initialization code has to happen at some point. None of `its constructors
<https://en.cppreference.com/w/cpp/container/unordered_set/unordered_set>`_ is
flagged as ``constexpr`` so the initialization happens at startup, before the
call to the ``main`` function.

Why is it worth a warning? The `clang manual
<https://clang.llvm.org/docs/DiagnosticsReference.html#wglobal-constructors>`_
is not very talkative on the subject, and the `commit introducing the feature
<https://github.com/llvm/llvm-project/commit/47e40931c9af037ceae73ecab7db739a34160a0e>`_
is not super helpful either, but it's `getting better <https://github.com/llvm/llvm-project/pull/68084>`_.
We can guess the reasons: it can cause bugs (think `Static Initialization
Order Fiasco <Static Initialization Order Fiasco>`_) and performance problems
(increased startup time).

Warming up
==========

The variable ``colors`` is a set that doesn't change in size after
initialization.
*Back in the days* I designed a small header-only C++ library called `frozen
<https://github.com/serge-sans-paille/frozen/issues>`_ that provides *à la*
Python frozen containers that match the standard library interface, let's use
this:

.. code-block:: c++

    #include <iostream>
    #include <cstring>
    #include "frozen/unordered_set.h"
    #include "frozen/string.h"

    using namespace frozen::string_literals;

    constexpr frozen::unordered_set<frozen::string, 3> primary_colors = {"red"_s, "green"_s, "blue"_s};

    int main(int argc, char const ** argv) {
      frozen::string color = argc > 1 ? frozen::string(argv[1], std::strlen(argv[1])) : "pink"_s;
        return primary_colors.count(color) ? 0 : 1;
    }

Changing a few namespaces, swapping a few headers and add some string literals and a
container size, and we're done:

.. code-block:: shell

   $ clang++ frozen_colors.cpp -Wall -Wglobal-constructors -O2 -o frozen_colors && ./frozen_colors green && echo ok
   ok

Great! No warning, job done! Job done? Let's double check the binary and run:

.. code-block:: shell

   $ nm -C frozen_colors | grep _GLOBAL__
   0000000000401070 t _GLOBAL__sub_I_frozen_colors.cpp

That's a bit suspicious, let's have a look at this symbol:

.. code-block:: shell

    $ objdump -C -S --disassemble=_GLOBAL__sub_I_frozen_colors.cpp frozen_colors
    [...]
    0000000000401070 <_GLOBAL__sub_I_frozen_colors.cpp>:
      401070:	50                   	push   %rax
      401071:	bf 3d 40 40 00       	mov    $0x40403d,%edi
      401076:	e8 d5 ff ff ff       	call   401050 <std::ios_base::Init::Init()@plt>
      40107b:	bf 60 10 40 00       	mov    $0x401060,%edi
      401080:	be 3d 40 40 00       	mov    $0x40403d,%esi
      401085:	ba 08 20 40 00       	mov    $0x402008,%edx
      40108a:	58                   	pop    %rax
      40108b:	e9 b0 ff ff ff       	jmp    401040 <__cxa_atexit@plt>
      [...]

Ah ah, ``<iostream>``. The header was included out of habit in the example
(totally by accident, not hand-crafted at all), and it didn't get reported
by clang because it comes from a system header. Removing the useless header is
indeed enough to get rid of the last global constructor of our toy program (note
that we no longer have any destructor at exit either). And now that we have set
the basics, let's start…

Digging Into Firefox's global constructor
=========================================

There's still a lot of C++ code in Firefox's codebase. Statistically, there
should be at least a dozen global constructors in it. A dozen? Hundreds!
`This Bug <https://bugzilla.mozilla.org/show_bug.cgi?id=1845263>`_ tracks the
various attempt to remove some of them, the rest of this article is just a
collection of the various situation in which global constructors have been
successfully removed so far.


Bye bye, ``<iostream>``
-----------------------

Using the example above, we can adopt a very simple strategy to detect all compilation units that include ``<iostream>``:

.. code-block:: shell

   objdump -C -d dist/bin/libxul.so > libxul.S  # cache this call as it takes a lot of time
   nm -C dist/bin/libxul.so | awk '/_GLOBAL__/ { print $3 }' | while read sym ; do grep $sym libxul.S -A8 | grep -q std::ios_base::Init && echo $sym; done

Then depending on the situation, we can decide what to do with the headers:

1. Keep it. Required if ``std::cout`` or ``std::cerr`` (or ``std::clog``!) are
   used

2. Replace it by ``<istream>`` or ``<ostream>``, when only that part of the API
   is needed, typically when only ``std::ostream`` or
   ``std::istream`` are used.

3. Remove it. This header is often included for debugging purpose and one
   forgets to remove it. Including myself ;-)

I've done so in `Bug 1855955
<https://phabricator.services.mozilla.com/D189648>`_, but also in `Bug 1854575
<https://phabricator.services.mozilla.com/D188949>`_ which was very satisfying
because it removed the include from a google protobuf file, which was included
in 33 compilation units! The patch also got `accepted in the upstream protobuf
repo <https://github.com/protocolbuffers/protobuf/pull/14174>`_.

Let it go, ``<frozen/*.h>``
---------------------------

It is very common to have small hash tables to store data mapping, and the
Firefox codebase typically have those:

- storing `mapping between string and enums
  <https://phabricator.services.mozilla.com/D189199>`_, a `very common pattern
  <https://phabricator.services.mozilla.com/D189201>`_;

- storing an `allow list <https://phabricator.services.mozilla.com/D189200>`_
  (well, of a single element…)

- storing an `array with a lot of holes as a map
  <https://phabricator.services.mozilla.com/D189202>`_ which is more memory
  efficient.

All these commits have not landed yet, but I'm very happy to revive this classic
I developed `5 years ago
<https://blog.quarkslab.com/frozen-zero-cost-initialization-for-immutable-containers-and-various-algorithms.html>`_.

Hello, ``constexpr``
--------------------

The firefox code base `uses C++17
<https://bugzilla.mozilla.org/show_bug.cgi?id=1768116>`_, so `constinit
<https://en.cppreference.com/w/cpp/language/constinit>`_ is not a thing, but
`constexpr` variables `must be immediately initialized
<https://en.cppreference.com/w/cpp/language/constexpr>`_ which implies no global
constructor.

Sometimes, just setting the constructor and/or the declaration as ``constexpr`` is enough. Easy!

Many time the variable is a ``static`` ``const`` global ``std::string`` in the Firefox code
base. They can be replaced by the internal ``nsLiteralCString`` class or by an
``std::string_view`` depending on the code they need to interact with. In both
cases we save the runtime initialization of the string while keeping the nice
encapsulation. We've done so in `Bug 1854969
<https://phabricator.services.mozilla.com/D189140>`_ and `Bug 1854490
<https://phabricator.services.mozilla.com/D188888>`_.

Special mention to `Bug 563351
<https://phabricator.services.mozilla.com/D184550>`_ where making a constructor
``constexpr`` and declaring a single variable as a *constexpr variable* got rid of a global constructor for a static variable declared in a header, thus in all files including that header.

`Bug 1854410 <https://phabricator.services.mozilla.com/D188842>`_ was somehow
similar: static variables in a header. This time the object could not be made
``constexpr``, but moving the initialization to the implementation file and
having external variables decreased the overall number of duplication.


Measuring the Impact
====================

Theoretically, these change should impact:

1. Code size, as the initialization code is no longer needed;

2. Startup time, as less code is executed at startup;

3. Lookup time (in the case of frozen structures) because
   ``frozen::unordered_(set|map)`` use perfect hashing, and ``frozen::(set|map)``
   use branch-less partitioning.

Point 1. may be balanced by the increase in data size (after all, the
``constexpr``-initialized data structure must live somewhere). It turns out that
in the case of firefox, the resulting ``libxul.so`` is smaller by a dozen of kB
after all the above changes.

Unfortunately, Point 2. and 3. are within the measurement noise on my setup.

Factually, those are not tremendous result, but let's not forget Point 4.:
Things have been learnt in the process, and shared through this write up ;-)


Acknowledgment
--------------

Thanks to Sylvestre Ledru and Paul Adenot for proof-reading this post, and to all the reviewers
of the above patches!
