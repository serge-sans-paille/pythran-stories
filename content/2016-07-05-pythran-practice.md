Title: Learn Pythran by practice
Date: 2016-07-04
Category: examples
Lang: en
Authors: pbrunet
Summary: Show Pythran usage on multiple kernels with its strengths and its weaknesses

Pythran presentation hold on Université Lyon1 on Monday 27th June together with a Julia presentation.

You can get slides shown by serge-sans-paille [here](http://serge-sans-paille.github.io/talks/python-perf-2016-06-27.html).

After this presentation, some examples were proposed to see Pythran usage.

# First example: Euler project N°14

## Problem

You can find Euler's project problems [here](https://projecteuler.net/problem=14).

The following iterative sequence is defined for the set of positive integers
n -> n/2 (n is even)
n -> 3n + 1 (n is odd)

Using the rule above and starting with 13, we generate the following sequence:
13 -> 40 -> 20 -> 10 -> 5 -> 16 -> 8 -> 4 -> 2 -> 1

It can be seen that this sequence (starting at 13 and fiinishing at 1) contains
10 terms.
Although it has not been proved yet (Collatz Problem), it is thought that all
starting numbers finish at 1.

Which starting number, under one million, produces the longest chain?

NOTE: Once the chain starts the terms are allowed to go above one million.

## Running the script

We need to get the maximum length of each values.

```python
>>> def run():
...     max_k, max_v = 1, 0
...     for i in xrange(1000000):
...         new_len = collatz_chain_length(i)
...         if new_len > max_v:
...             max_k, max_v = i, new_len
...     return max_k
```

Now, we just need to compute the length of the chain for a given value.

## A recursive solution

Searching on the internet, one can find solutions like [here](https://www.lucaswillems.com/fr/articles/40/project-euler-14-solution-python)
or [here](https://github.com/nayuki/Project-Euler-solutions/blob/master/python/p014.py)

```python
>>> def collatz_chain_length(x):
...     if x not in collatz_cache:
...         if x % 2 == 0:
...             y = x // 2
...         else:
...             y = x * 3 + 1
...     collatz_cache[x] = collatz_chain_length(y) + 1
...     return collatz_cache[x]
```

This recursive version needs a global variable to cache data as Python is limited by the recursion depth.
As Pythran can't handle non constant globals, we will pass this variable as a second argument

Now time it

```bash
$ python -c "import prob_14; print prob_14.run()"
837799
$ python -m timeit -s "import prob_14" "prob_14.run()"
10 loops, best of 3: 1.26 msec per loop
```

<!-- It is 189 msec with the globals variable but I don't understand why it is so fast... -->

OK, this is our reference execution time.

## Imperative solution

We can perform the direct computation:

```python
>>> def collatz_chain_length(x):
...     count = 0
...     while x > 1:
...         if x % 2 == 0:
...             x = x / 2
...         else:
...             x = x * 3 + 1
...         count += 1
...     return count
```

Now time it

```bash
$ python -c "import prob_14; print prob_14.run()"
837799
$ python -m timeit -s "import prob_14" "prob_14.run()"
10 loops, best of 3: 12.8 sec per loop
```

This solution is slower as it compute everything for each value (no caching mechanism)

## Pythranize the solution

Look at the imperative solution. We just add in the .py file:

`# pythran export run()`

```bash
$ python -m pythran.run prob_14.py
$ python -c "import prob_14; print prob_14.run()"
837799
$ python -m timeit -s "import prob_14" "prob_14.run()"
10 loops, best of 3: 626 msec per loop
```

Result is the same (hopefully...) but it is 20x faster with no effort.
As we use native library, we can go without the [GIL](https://wiki.python.org/moin/GlobalInterpreterLock)
and use Pythran OpenMP extension:

```python
>>> # pythran export run()
>>> def run():
...     max_k, max_v = 1, 0
...     # omp parallel for
...     for i in xrange(1, 1000000):
...         new_len = collatz_chain_length2(i)
...         # omp critical
...         if new_len > max_v:
...             max_k, max_v = i, new_len
...     return max_k
```

```bash
$ python -m pythran.run prob_14.py -fopenmp
$ python -c "import prob_14; print prob_14.run()"
837799
$ python -m timeit -s "import prob_14" "prob_14.run()"
10 loops, best of 3: 210 msec per loop
```

My computer is have 4 CPU and there is another 3x speed up. Which is finally a nice 60x speed up.
It is good but still slower than the recursive function as it doesn't cache values.


Let's look at the recursive solution.

```bash
$ python -m pythran.run prob_14.py
$ python -c "import prob_14; print prob_14.run()"
837799
$ python -m timeit -s "import prob_14" "prob_14.run()"
10 loops, best of 3: 968 msec per loop
```

We get a 1.3x speed up which is almost nothing. This example show that Python is
not so bad with high level construct like dictionary. As we spend most of the
time looking and hashing data in dictionary, it is already a native code in Python
and we are not really faster with Pythran.

## Conclusion

If we use high level construct, Python may be the good tool as native code will
not be really faster but if we perform a lot of computation, using Pythran may
be really benefit. Finally, a *slow* solution with Python may be a *fast* native
code solution while a *fast* Python solution may be a *slow* native code solution.

## Fun fact

If we add a dummy function:

```python
>>> # pythran export dummy()
>>> def dummy():
...    return run()
```

```bash
$ python -m pythran.run prob_14.py
$ python -c "import prob_14; print prob_14.dummy()"
837799
$ python -m timeit -s "import prob_14" "prob_14.dummy()"
10000000 loops, best of 3: 0.0415 usec per loop
```

This happen because this computation doesn't have any side effect so Pythran
compute the result at compile time and `dummy()` only give the pre-computed result.


# Second example: rbf network

This code is extracted from [here](http://nealhughes.net/cython1/).

Example function evaluates a Radial Basis Function (RBF) approximation scheme.

So that everybody works with the same kind of data, we will setup env with:

```python
>>> import numpy as np
>>> D = 5
>>> N = 1000
>>> X = np.array([np.random.rand(D) for d in range(N)])
>>> beta = np.random.rand(N)
>>> theta = 10
```

Original code is:

```python
>>> def rbf_network(X, beta, theta):
... 
...     N = X.shape[0]
...     D = X.shape[1]
...     Y = np.zeros(N)
... 
...     for i in range(N):
...         for j in range(N):
...             r = 0
...             for d in range(D):
...                 r += (X[j, d] - X[i, d]) ** 2
...             r = r**0.5
...             Y[i] += beta[j] * np.exp(-(r * theta)**2)
... 
...     return Y
```

First, we time the original solution.

```bash
$ python -m timeit -s "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;import origin" "origin.rbf_network(X, beta, theta)"
10 loops, best of 3: 4.09 sec per loop
```

## Turn Python kernel to Numpy kernel

Numpy mostly run as native code. Using its broadcasting feature permit to use more native code and thus, run it faster.

```python
>>> def rbf_network_numpy(X, beta, theta):
...     return (beta * np.exp(-(np.sqrt(((X[:, None, :] - X) ** 2).sum(-1)) * theta) ** 2)).sum(-1)
```

With this pure Numpy code, we first check result:

```bash
$ python -c "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;import origin; print np.allclose(origin.rbf_network_numpy(X, beta, theta), origin.rbf_network(X, beta, theta))"
True
```

Then, we can time it:

```bash
$ python -m timeit -s "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;import origin" "origin.rbf_network_numpy(X, beta, theta)"
10 loops, best of 3: 73.6 msec per loop
```

and it is 55x faster.

This speed can be enough for our case then, we can use only Python code and everything is fine.
We can also use Pythran to make it even faster.

## Use Pythran on rbf network

Once again, we just add the pythran comment:
`# pythran rbf_network(float[][], float[], float)`

We check the result

```bash
$ python -c "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;import origin;import origin_python;print np.allclose(origin.rbf_network_numpy(X, beta, theta), origin_python.rbf_network(X, beta, theta))"
True
```

And we time it

```bash
$ python -m timeit -s "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;import origin" "origin.rbf_network_numpy(X, beta, theta)"
10 loops, best of 3: 67.4 msec per loop
```

It is already slightly faster than Numpy.

To be even faster, we generate beta version to vectorize code:

```bash
$ python -m pythran.run origin.py -Ofast -march=native -DUSE_BOOST_SIMD
$ python -m timeit -s "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;import origin" "origin.rbf_network_numpy(X, beta, theta)"
10 loops, best of 3: 26.1 msec per loop
```

## Scipy.rbf


Scipy also provide rbf function but if we time it, we have:

```bash
$ python -m timeit -s "import numpy as np;D = 5;N = 1000;X = np.array([np.random.rand(D) for d in range(N)]);beta = np.random.rand(N);theta = 10;from scipy.interpolate import Rbf;rbf = Rbf(X[:,0], X[:,1], X[:,2], X[:,3], X[:, 4], beta);Xtuple = tuple([X[:, i] for i in range(D)]);" "rbf(Xtuple)"
10 loops, best of 3: 258 msec per loop
```

Which is slower than Numpy version. Certainly because this function is much more generic than our.


## Conclusion

Pure Numpy kernel is almost as fast as native kernel and we should not bother with accelerator
if we don't need more performances. If we need more, Pythran can give a 3x speed up on it mainly because it can generate SIMD code thanks to Boost.SIMD

# Third (and last) example: mandelbrot

Most of the time, our Python code use more than modules provided by Pythran but we still need performance.

Here is an example from [rosetacode](http://rosettacode.org/)

```python
>>> from pylab import *
>>> from numpy import NaN

>>> def m(a):
... 	z = 0
... 	for n in range(1, 100):
... 		z = z**2 + a
... 		if abs(z) > 2:
... 			return n
... 	return NaN

>>> X = arange(-2, .5, .002)
>>> Y = arange(-1,  1, .002)
>>> Z = zeros((len(Y), len(X)))

>>> for iy, y in enumerate(Y):
... 	print (iy, "of", len(Y))
... 	for ix, x in enumerate(X):
... 		Z[iy,ix] = m(x + 1j * y)

>>> imshow(Z, cmap = plt.cm.prism, interpolation = 'none', extent = (X.min(), X.max(), Y.min(), Y.max()))
>>> xlabel("Re(c)")
>>> ylabel("Im(c)")
>>> savefig("mandelbrot_python.svg")
>>> show()
```

As Pythran doesn't handle graphics modules like pylab, we need to separate computation intensive part and
graphics code.

`my_module.py`
```python
>>> import numpy as np

>>> def m(a):
... 	z = 0
... 	for n in range(1, 100):
... 		z = z**2 + a
... 		if abs(z) > 2:
... 			return n
... 	return np.NaN

>>> def mandel(X, Y):
... 	Z = np.zeros((len(Y), len(X)))
... 
... 	for iy, y in enumerate(Y):
... 		for ix, x in enumerate(X):
... 			Z[iy,ix] = m(x + 1j * y)
... 	return Z
```

`script.py`
```python
>>> from pylab import *
>>> from my_module import mandel

>>> X = arange(-2, .5, .002)
>>> Y = arange(-1,  1, .002)
>>> Z = mandel(X, Y)

>>> imshow(Z, cmap = plt.cm.prism, interpolation = 'none', extent = (X.min(), X.max(), Y.min(), Y.max()))
>>> xlabel("Re(c)")
>>> ylabel("Im(c)")
>>> savefig("mandelbrot_python.svg")
>>> show()
```

Now, we can time and improve the mandel function.

```bash
$ time python -c "import numpy as np;X = np.arange(-2, .5, .002);Y = np.arange(-1,  1, .002); import my_module; my_module.mandel(X, Y)"

real	0m19.495s
user	0m19.476s
sys	0m0.016s
```

I use time here as I want a one show as it is a really long run.

After using Pythran on it, we have:

```bash
$ python -m pythran.run my_module.py
$ python -m timeit -s "import numpy as np;X = np.arange(-2, .5, .002);Y = np.arange(-1,  1, .002); import my_module" "my_module.mandel(X, Y)"
10 loops, best of 3: 538 msec per loop
```

It is 40 times faster and graphics part are still possible through Python.

There is no need to try with SIMD as it doesn't work on complex numbers.

# Conclusion

I hope these examples show what performance can be reach using Python/Numpy and
when you need to use an accelerator to generate faster native code.
