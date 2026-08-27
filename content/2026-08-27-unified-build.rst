Pros and Cons of Unified Build
##############################

:date: 2026-08-27
:category: mozilla
:lang: en
:authors: serge-sans-paille
:summary: Some thoughts on unified build, based on the experience gathered on Firefox codebase.

Unified builds (also know as *Jumbo Builds*) is a build techniques that aims at
improving build time through the concatenation of several sources as a single
*unified* source before compilation.

The goal is obtained through implicit caching of header instantiation, although it
implies a trade-off with parallelism.

Let's illustrate this behavior through a simple example, two codes that implement variation of the same approach:

.. code-block:: c++

   /* algo0.cpp */
   #include <iostream>
   #include <string>
   #include <vector>
   void translate(std::vector<std::string>& w, void (&t)(std::string&));
   void translate(std::vector<std::string>& w_out, std::vector<std::string> const & w_in, void (&t)(std::string&)) {
       std::cout << "[log] through transform\n";
       w_out = w_in;
       translate(w_out, t);
   }

   /* algo1.cpp */
   #include <algorithm>
   #include <iostream>
   #include <string>
   #include <vector>
   void translate(std::vector<std::string>& w, void (&t)(std::string&)) {
       std::cout << "[log] through for_each\n";
       std::for_each(w.begin(), w.end(), [&t](std::string& s) { t(s); });
   }

Compiling individual files take the following times:

.. code-block:: sh

    % hyperfine --warmup 5 "/usr/bin/clang++ -O2 algo0.cpp -c"
    Benchmark 1: /usr/bin/clang++ -O2 algo0.cpp -c
      Time (mean ± σ):     267.7 ms ±   7.4 ms    [User: 234.6 ms, System: 30.4 ms]
      Range (min … max):   259.7 ms … 277.3 ms    11 runs

    % hyperfine --warmup 5 "/usr/bin/clang++ -O2 algo1.cpp -c"
    Benchmark 1: /usr/bin/clang++ -O2 algo1.cpp -c
      Time (mean ± σ):     173.6 ms ±  46.3 ms    [User: 149.6 ms, System: 22.1 ms]
      Range (min … max):   130.4 ms … 231.6 ms    13 runs


Creation of the unified file is just a matter of invoking ``cat``, let's
benchmark the compilation of the unified source:

.. code-block:: sh

    % cat algo{0,1}.cpp > unified_algo.cpp
    % hyperfine --warmup 5 "/usr/bin/clang++ -O2 unified_algo.cpp -c"
    Benchmark 1: /usr/bin/clang++ -O2 unified_algo.cpp -c
      Time (mean ± σ):     223.8 ms ±  64.5 ms    [User: 193.0 ms, System: 28.4 ms]
      Range (min … max):   160.8 ms … 301.8 ms    10 runs

In that simple case, the weight of headers with respect to actual user code is such that
compilation of the unified file takes almost the same time as the max compilation time among each individual file. That's roughly a 1.97x speedup on compilation time.

That's the promise given by unified builds. And it's a promise held.

Now let's have a look at the consequences of that deal.

Beforehand, we still need to introduce another parameter tied to unified builds: the
*unification parameter*, say ``P``. That parameter bounds the number of files
that are unified together. Let's imagine we have a hundred of individual source
files compiled with exactly the same compilation flags. Setting ``P`` to ``5``
leads to the generation of ``20`` unified sources compiled independently.

Remember the parameter ``P``.

Quality of the Generated Code
-----------------------------

Let's create a shared object from ``algo{0,1}.o`` (this implies a recompilation with ``-fPIC`` of the sources):

.. code-block:: sh

    % /usr/bin/clang++ -O2 algo0.cpp -c -fPIC
    % /usr/bin/clang++ -O2 algo1.cpp -c -fPIC
    % /usr/bin/clang++ -shared algo{0,1}.o -fPIC -o algo.so

And do the same from ``unified_algo.o``:

.. code-block:: sh

    % /usr/bin/clang++ -O2 unified_algo.cpp -c -fPIC
    % /usr/bin/clang++ -shared unified_algo.o -fPIC -o unified_algo.so

After stripping, comparing the size of the binaries yield a difference of a few bytes. After disassembling, it turns out the compiler decides to inline the call to ``void translate(std::vector<std::string>& w, void (&t)(std::string&))`` from ``algo0.cpp`` when compiling the unified source, something the compiler cannot do when doing split compilation, as it does *not* know anything about the implementation of that function.

Interestingly, compiling with ``-flto=thin`` still lead the compiler instantiation through different optimization path.

Falling back to ``-flto=full`` finally yields to the same shared object, which makes sense because Full LTO is very close to performing source unification at the bytecode level *and* our sources are very simple. It's not a given though because the actual optimisation pipeline is still different in the two scenario.

Why does it matter? Depending on the value of ``P``, the compiler will see
different sets of files per unified file, which will result in different binary
code. It's actually even worse: depending on the way we fill those unification
sets, event with the same parameter ``P``, we end up with different binaries.
Let's call that the *reunifying problem*.

Even if we have an algorithm that seems to guarantee reproducibility, for
instance working on a sorted list of files with a fixed ``P``, variation can
arise: the introduction of a new source file can lead to changes in every
unified file (e.g. if the split is done by chunks and the new file ends up at
the beginning of the file list).

So **unified builds tend to improve performance, but they do not interact in a gentle way with performance reproducibility**.

Recompilation Times
-------------------

Let's denote ``S`` as the number of sources and ``C`` as the number of CPUs.

Intuitively, setting ``P=1`` yields to the faster recompilation time when a
single file is touched---a usual scenario when developing a new feature.

On the opposite, setting ``P=S`` yields to the slower recompilation time (if ``S >>
C``!) under the same scenario as all sources are recompiled under that
scenario.

The form of the curve between those two extreme varies depending on the nature
of the files, and the amount of header sharing between individual sources.

Caching tools like ``sccache`` is impacted by the same mechanism: as ``P`` gets
greater, more cache misses are hit and more recompilation are done.

Marginally, introducing a new source also pollutes the cache or triggers
recompilation for the unified source it gets added to, and eventually for all
the unified sources derived from the associated file list. The *reunifying problem* strikes again.

So **unified build make compilation faster, but recompilation slower**. Setting
``P`` to an acceptable value is important depending on the usage scenario.

Correctness
***********

Unified build changing the compilation unit frontier, which in turns *modifies
the semantic of the program*. This change can be straight-forward or complex to
debug, and even remain silent. I've listed a few instances of the two first
categories below, and a crafted one for the latter category.

Macro / Symbol Redefinition
+++++++++++++++++++++++++++

This one is trivial to spot (a preprocessor-warning is issued for the macro,
and a compiler error is issued for the symbol redefinition):

.. code-block:: c++

    /* pi0.cpp */
    #define PI 3.141593
    constexpr double pi() { return 3.141593; }

    /* pi1.cpp */
    #define PI 3.14159265
    constexpr double pi() { return 3.14159265; }

The solution usually lies in moving the definition in a shared header, moving the declaration in a shared header and the definition in a single file, or renaming identifiers to avoid the name conflict. Note that depending on the solution we may change the visibility of the symbols, or impact code readability (assuming the identifier name was perfectly chosen in the first place).

Overload Conflicts
++++++++++++++++++

This one is also trivial to spot and may hint toward debatable design. But it exists and may be more complex to understand than the above:

.. code-block:: c++

    /* overload0.cpp */
    static float doit(float f) { return f;}
    const float f = doit(1);

    /* overload1.cpp */
    static double doit(double d) { return d;}
    const double d = doit(1);

The fix is generally to provide a perfect match for the overload, change the call site to avoid the ambiguity, or rename the functions/change their namespace to make the call site explicit.


Using Namespace Confusion
+++++++++++++++++++++++++

This one tends to creep a lot in codebase where ``using namespace`` is used. It generates ambiguity among potential symbols.

A caricatured situation is exhibited with the following situation:

.. code-block:: c++

   /* using.h */
   #pragma once
   namespace a {
       namespace a {}
   }

   /* using0.cpp */
   #include "using.h"
   using namespace a;

   /* using1.cpp */
   #include "using.h"
   using namespace a;

Once ``using{0,1}.cpp`` unified, the second ``using namespace a;`` directive is ambiguous.

A more realistic (but similar in spirit) situation arises when the same symbol is defined in different namespaces:

.. code-block:: c++

   /* namespace0.cpp */
   namespace a0 {
       int var;
   }
   using namespace a0;
   int foo = var;

   /* namespace1.cpp */
   namespace a1 {
       int var;
   }
   using namespace a1;
   int bar = var;

The problem with that category is that the fix is quite unsatisfying: there is no way to limit the scope of a ``using`` directive, removing ``using`` directive can lead to very verbose codebase, renaming symbols to avoid conflicts goes against the very purpose of namespaces...

Delicatessen
++++++++++++

I spent a lot of time nailing that one down, so I wrote a small reproducer to illustrate the problem.

.. code-block:: sh

    % tail -n +1 *.h *.cpp
    ==> header0.h <==
    #ifndef H0
    #define H0
    namespace mozilla::dom {

    class Lock final {};

    }
    #endif

    ==> header1.h <==
    #ifndef H1
    #define H1

    #include "header0.h"

    class Lock {};

    class AutoUnlock {
        Lock *lock_;
    };
    #endif

    ==> src0.cpp <==
    #include "header1.h"

    ==> src1.cpp <==
    #include "header0.h"

    ==> src2.cpp <==
    namespace mozilla::dom {};
    using namespace mozilla::dom;
    using namespace mozilla;


    ==> src3.cpp <==
    #include "header1.h"

Let me comment that layout a bit: We basically have two different classes named ``Lock``: one lives in the ``mozilla::dom`` namespace, and one lives at top-level. In ``header1.h``, although we include the definition of ``mozilla::dom::Lock``, we also get the definition of ``::Lock``, so a straight reference to ``Lock`` is not ambiguous.

Concerning source files, ``src0.cpp``, ``src1.cpp`` and ``src3.cpp`` just include headers while ``src2.cpp`` contains the infamous ``using namespace modilla::dom;`` statement.

Let's now consider various partition of the file list ``src0.cpp, src1.cpp, src2.cpp, src3.cpp``:

.. code-block:: sh

    % for perm in 0,1 2,3 0,1,2 1,2,3 0,1,2,3; do printf "unifying $perm... " ; cat `eval echo src{$perm}.cpp` | clang++ -xc++ - -fsyntax-only 2>/dev/null && echo ok || echo ko ; done
    unifying 0,1... ok
    unifying 2,3... ko
    unifying 0,1,2... ok
    unifying 1,2,3... ko
    unifying 0,1,2,3... ok

Isn't that amazing? Some intermediate unification, namely ``0,1;2,3`` and ``0;1,2,3`` fail, but other unifications, namely ``0,1,2,3`` and ``0;1,2,3`` fail. Did you notice that both non-unified and full unified build succeeds, while some intermediate unification fail? What a disaster. This basically mean that given a set of sources, and without putting restriction on the language (like banning ``using`` statement), the only way to be sure that a unified build always succeeds whatever the chosen partition is to test every partition. Not very satisfying.

As a side effect, we can also deduce that adding a new source file to a set of files to be unified can break compilation in files that used to compile fine. That's another instance of the *reunifying problem*.

Changing Semantic
+++++++++++++++++

It is quite easy to derive from the above an example whose semantic change once unified. Let's slightly change the overload conflict example from above:

.. code-block:: c++

    /* silent0.cpp */
    #include <cstdio>
    static int doit(int f) { putchar('0'); return f;}
    const int f = doit(1);

    /* silent1.cpp */
    #include <cstdio>
    static double doit(double d) { putchar('1'); return d;}
    const double d = doit(1);

When compiled independently, this results in a binary that prints a ``0`` and a ``1`` on the screen. But when compiled as a unified source, we only get a pair of ``0``.

Concluding Words
****************

Remember that discussion between Luke and Yoda?

    LUKE
    Vader. Is the dark side stronger?

    YODA
    No… no… no. Quicker, easier, more seductive.

That's exactly my thoughts on unified builds: they give you quick wins in
term of cold build speed and give faster builds. That's very good
properties, and you rip the benefit of them very quickly. Then you realize
that you're tied to a monster in terms of maintainability and developer
experience, but you're already addict to the speed it gave you.
