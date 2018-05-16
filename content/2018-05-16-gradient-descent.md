Title: An incursion into basic ML - Gradient Descent compiled with Pythran
Date: 2018-05-16
Category: optimisation
Lang: en
Authors: serge-sans-paille
Summary: Or how to compile a basic kernel from the machine learning field with Pythran.

This blogpost originally was a Jupyter Notebook. You can [download it](notebooks/An incursion into basic ML - Gradient Descent compiled with Pythran.ipynb) if you want. The conversion was done using ``nbconvert`` and a [custom template](notebooks/nbmarkdown.tpl) to match the style of the other part of the blog.

Thanks to w1gz and Apo for their review!

In https://realpython.com/numpy-tensorflow-performance/, the author compares the performance of different approaches of a basic ML kernel, gradient descent. 

Let's try to join the party :-) 


```python
>>> import pythran
>>> %load_ext pythran.magic
```

Original Setup
=========

The original Numpy code is the following:


```python
>>> import numpy as np
>>> import itertools as it
... 
>>> def np_descent(x, d, mu, N_epochs):
...     d = d.squeeze()
...     N = len(x)
...     f = 2 / N
... 
...     y = np.zeros(N)
...     err = np.zeros(N)
...     w = np.zeros(2)
...     grad = np.empty(2)
... 
...     for _ in it.repeat(None, N_epochs):
...         np.subtract(d, y, out=err)
...         grad[:] = f * np.sum(err), f * (err @ x)
...         w = w + mu * grad
...         y = w[0] + w[1] * x
...     return w
```

And the experimental setup is the following: 


```python
>>> import numpy as np
... 
>>> np.random.seed(444)
... 
>>> N = 10000
>>> sigma = 0.1
>>> noise = sigma * np.random.randn(N)
>>> x = np.linspace(0, 2, N)
>>> d = 3 + 2 * x + noise
>>> d.shape = (N, 1)
... 
>>> mu = 0.001
>>> N_epochs = 10000
```

So our base line is:


```python
>>> %timeit np_descent(x, d, mu, N_epochs)
```

    281 ms ± 9.82 ms per loop (mean ± std. dev. of 7 runs, 1 loop each)


Pythran version
=========

the implicit contract with pythran is ‘add a comment and compile’, but in that case we made two changes:

1. static ``squeeze`` because pythran does not support dynamic array dimensions
2. remove the ``out`` parameter for ``np.subtract`` because it's not supported yet by pythran (but it could in the future)


```python
>>> %%pythran
>>> import numpy as np
>>> import itertools as it
... 
>>> #pythran export pythran_descent(float64[], float64[,], float, int)
>>> def pythran_descent(x, d, mu, N_epochs):
...     assert d.shape[1] == 1, "pythran does not support squeeze"
...     d = d.reshape(d.shape[0])
...     N = len(x)
...     f = 2 / N
... 
...     y = np.zeros(N)
...     err = np.zeros(N)
...     w = np.zeros(2)
...     grad = np.empty(2)
... 
...     for _ in it.repeat(None, N_epochs):
...         err[:] = d - y
...         grad[:] = f * np.sum(err), f * (err @ x)
...         w = w + mu * grad
...         y = w[0] + w[1] * x
...     return w
```

Ok, it compiles fine, let's run it!


```python
>>> %timeit pythran_descent(x, d, mu, N_epochs)
```

    268 ms ± 5.05 ms per loop (mean ± std. dev. of 7 runs, 1 loop each)


That's slightly faster, but not by much. The numpy code is actually pretty good already, and a good chunk of the time is spent in the scalar product; there is not much to gain here as both numpy and pythran fallback to blas.

SIMD Instructions to the rescue
------------------------------------

Pythran supports generation of SIMD instructions, through the great Boost.SIMD library. Let's update compile flags and try again. The ``-march=native`` tells the underlying compiler (here, GCC 7.3.0) to generate code specific to my processor's architecture, thus enabling AVX instructions \o/


```python
>>> %%pythran -DUSE_BOOST_SIMD -march=native
>>> import numpy as np
>>> import itertools as it
... 
>>> #pythran export pythran_descent_simd(float64[], float64[,], float, int)
>>> def pythran_descent_simd(x, d, mu, N_epochs):
...     assert d.shape[1] == 1, "pythran does not support squeeze"
...     d = d.reshape(d.shape[0])
...     N = len(x)
...     f = 2 / N
... 
...     y = np.zeros(N)
...     err = np.zeros(N)
...     w = np.zeros(2)
...     grad = np.empty(2)
... 
...     for _ in it.repeat(None, N_epochs):
...         err[:] = d - y
...         grad[:] = f * np.sum(err), f * (err @ x)
...         w = w + mu * grad
...         y = w[0] + w[1] * x
...     return w
```


```python
>>> %timeit pythran_descent_simd(x, d, mu, N_epochs)
```

    114 ms ± 298 µs per loop (mean ± std. dev. of 7 runs, 10 loops each)


Now *that* is fast \o/

The long story
========

When I first tried to port the kernel, there was two limitations in Pythran. They are now merged into master but not in current release (0.8.5).

1. There was no support for ``itertools.repeat``. Pythran already supports a bunch of the ``itertools`` interface, so even if it's a bit overkill in that context, i added the support and the tests for that call.

2. Poor ``@`` performance. In the case of the scalar product of two arrays, openblas is much faster than the trivial non-vectorized implementation, so I specialized the pythran implementation of dot to fallback to the blas call when both parameters are arrays. In the more generic case, merging the operation is still a better approach


```python
>>> %%pythran -DUSE_BOOST_SIMD -march=native
>>> #pythran export dottest0(float[], float[])
>>> def dottest0(x, y):
...     from numpy import array
...     tmp = x + y
...     return x @ tmp, tmp
... 
>>> #pythran export dottest1(float[], float[])
>>> def dottest1(x, y):
...     from numpy import array
...     tmp = x + y
...     return x @ tmp, x
```


```python
>>> x = y = np.ones(1000000)
```


```python
>>> %timeit dottest0(x, y)
```

    1.74 ms ± 12.5 µs per loop (mean ± std. dev. of 7 runs, 1000 loops each)



```python
>>> %timeit dottest1(x, y)
```

    631 µs ± 33.1 µs per loop (mean ± std. dev. of 7 runs, 1000 loops each)


What happened? In ``dottest0``, ``tmp`` is used twice so a temporary array is created, and the ``@`` operator fallsback to blas implementation, as it is specialized in that case. For ``dottest1``, ``tmp`` is used once, so it is evaluated lazily and the ``@`` operator now has an array and a lazy expression as parameter: it computes this expression in a single (vectorized) loop.

Final Words
======

So here are the final timings from my little experiment. It's nice to get some speedups from high level code, and I should probably be able to improve the generated code in the future!

|Engine      | Execution Time (s)
-------------|--------------
|Numpy       | 0.281
|Pythran     | 0.268
|Pythran+SIMD| 0.114

