import numpy as np
cimport numpy as np
from libc.math cimport fabs

cimport cython
@cython.boundscheck(False) # turn off bounds-checking for entire function
@cython.wraparound(False)  # turn off negative index wrapping for entire function
def cy_py_laplacien(np.ndarray[double, ndim=2] image):
    cdef int i, j
    cdef int n = image.shape[0], m = image.shape[1]
    cdef np.ndarray[double, ndim=2] out_image = np.empty((n-2,m-2))
    cdef double valmax
    for i in range(n-2):
        for j in range(m-2):
            out_image[i,j] =  fabs(4*image[1+i,1+j] -
                       image[i,1+j] - image[2+i,1+j] -
                       image[1+i,j] - image[1+i,2+j])
    valmax = out_image[0,0]
    for i in range(n-2):
        for j in range(m-2):
            if out_image[i,j] > valmax:
                valmax = out_image[i,j]
    valmax = max(1.,valmax)+1.E-9
    for i in range(n-2):
        for j in range(m-2):
            out_image[i,j] /= valmax
    return out_image
