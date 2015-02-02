# cython: profile=False

from .storage cimport PersistentMeta, AssignedByReference, TypeDescriptor
from .storage cimport Offset, Storage
# from .query   cimport BindingRule
from cpython cimport PyObject, Py_buffer
from libc.string cimport memcpy, strlen

cdef extern from "Python.h":
    int PyBUF_FULL_RO, PyBUF_C_CONTIGUOUS, PyBUF_ANY_CONTIGUOUS, PyBUF_FORMAT
    int PyBUF_SIMPLE  # PyBUF_INDIRECT, PyBUF_STRIDES, PyBUF_ND
    int PyObject_CheckBuffer(object obj)
    int PyObject_GetBuffer(object  obj, Py_buffer *view, int flags) except -1
    int PyBuffer_ToContiguous(void *buf, Py_buffer *view, Py_ssize_t len,
                              char fort) except -1
    int PyBuffer_FillInfo(Py_buffer *view, object obj, void *buf,
                          Py_ssize_t len, int readonly, int infoflags
                          ) except -1

    # The below is not used due to http://bugs.python.org/issue15913
    # Py_ssize_t PyBuffer_SizeFromFormat(const char *)

    void PyBuffer_FillContiguousStrides(int nd, Py_ssize_t *shape,
                                        Py_ssize_t *strides, int itemsize,
                                        char fort)
    void PyBuffer_Release(Py_buffer *view)

import logging
LOG = logging.getLogger(__name__)

########################## Persistent Buffers ##############################
# Objective:
#   be able to store objects of any type that
#     1) support the buffer protocol
#            (https://docs.python.org/2/c-api/buffer.html)
#     2) the memory exposed via the buffer interface does not contain pointers
#     3) can reconstruct the object if given a buffer containing its data

# Persistent version of
#      https://github.com/python/cpython/blob/master/Include/object.h#L178-191
cdef:
    struct CBuffer:
        Offset   o2buf   # object.h: void *

        # The total length of the memory in bytes
        #    len = ((*shape)[0] * ... * (*shape)[ndims-1])*itemsize
        Py_ssize_t len

        # This is Py_ssize_t so it can be pointed to by strides in simple case
        Py_ssize_t itemsize
        int ndim
        Offset o2format  # object.h: char *
        Offset o2shape   # object.h: Py_ssize_t *
        Offset o2strides  # object.h: Py_ssize_t *

        # We do not use the following fields present in object.h:
        # int readonly - we always provide R/W access
        # char fortran='C' - We will always store stuff C-contiguously
        # Py_ssize_t * suboffsets - We do not support suboffsets
        #                                (we always set it to NULL)
        # void* internal - is not for the consumer

cdef class BufferMeta(PersistentMeta):
    # Reconstructors are not yet implemented!
    #     """ @param reconstructor: Python code that leaves in the local name
    #            space a reference to a callable under the name
    #           'reconstruct' when it is executed
    #     """
    #     cdef:
    #         object  reconstructor
    #         # a callable that can re-create the instance of the object from a
    #         # copy of its buffer
    #         object  reconstruct
    def __init__(ptype,
                 Storage       storage,
                 str           className,
                 type          proxyClass,
                 #                        object        reconstructor,
                 ):
        #         ptype.reconstructor = reconstructor
        localNameSpace = dict()
        globalNameSpace = dict()
#         exec (reconstructor, globalNameSpace, localNameSpace)
        ptype.reconstruct = localNameSpace.get('reconstruct')
        PersistentMeta.__init__(ptype, storage, className, proxyClass,
                                sizeof(CBuffer))

    def reduce(ptype):
        return ('_typedef', ptype.__name__, ptype.__class__, ptype.proxyClass,
                #                 ptype.reconstructor
                )

cdef class PBuffer(AssignedByReference):

    cdef inline CBuffer *getP2IS(PBuffer self):
        return <CBuffer *>self.p2InternalStructure

    def __init__(self, object value):
        cdef:
            Py_buffer view
            CBuffer *cBuffer = self.getP2IS()
            Py_ssize_t length, i

        # value must support the buffer interface
        if 0==PyObject_CheckBuffer(value):
            raise TypeError("Objects of type '{}' do not support the buffer "
                            "protocol.".format(type(value).__name__))

        # get the buffer
        # XXX assumption: PyObject_GetBuffer does not Py_INCREF(value)
        # PyBUF_FULL_RO = PyBUF_FORMAT  | PyBUF_INDIRECT
        #     (which implies PyBUF_STRIDES and indirectly PyBUF_ND)
        # so we will have shape, strides, suboffsets and format filled in
        if (PyObject_GetBuffer(value, &view, PyBUF_FULL_RO) < 0):
            raise BufferError("Could not get a buffer from {}.".format(value))

        assert view.obj is not None

        # save/copy the buffer into the persistent store
        if view.buf is not NULL:
            cBuffer.o2buf = self.ptype.storage.allocate(view.len)
            PyBuffer_ToContiguous(self.ptype.offset2Address(cBuffer.o2buf),
                                  &view, view.len, 'C')

            PyBuffer_FillContiguousStrides(view.ndim, view.shape, view.strides,
                                           view.itemsize, 'C')
#             view.strides[view.ndim-1] = view.itemsize
#             for i in range(view.ndim-1, 0, -1):
#                 view.strides[i-1] = view.strides[i] * view.shape[i]

        cBuffer.len = view.len

        if view.format is NULL:
            # PyBUF_FULL_RO = PyBUF_FORMAT | PyBUF_FULL_RO | PyBUF_INDIRECT | \
            #                 PyBUF_STRIDES | PyBUF_ND
            PyBuffer_FillInfo(&view, value, view.buf, view.len, 1,
                              PyBUF_FULL_RO)
        cBuffer.o2format = self.allocateAndCopy(view.format,
                                                strlen(view.format)+1)

#         if view.itemsize==0:
#             cBuffer.itemsize = PyBuffer_SizeFromFormat(view.format)
        cBuffer.itemsize = view.itemsize

        #cBuffer.readonly = view.readonly
        cBuffer.ndim = view.ndim

        LOG.debug("__init__ {} {} {}".format(cBuffer.o2format,
                                             cBuffer.itemsize, view.ndim))

        if view.ndim == 0:
            cBuffer.o2shape = cBuffer.o2strides = 0
        else:
            length = view.ndim * sizeof(Py_ssize_t)
            cBuffer.o2shape      = self.allocateAndCopy(view.shape, length)
            cBuffer.o2strides    = self.allocateAndCopy(view.strides, length)
            # We do not support suboffsets (we always set it to NULL)

        # release the buffer
        # XXX assumption: PyBuffer_Release does not Py_CLEAN(value)
        PyBuffer_Release(&view)

    cdef Offset allocateAndCopy(self, void* source, int length):  # XXX inline?
        if source==NULL:
            return 0
        cdef Offset targetOffset = self.ptype.storage.allocate(length)
        memcpy(self.ptype.offset2Address(targetOffset), source, length)
        return targetOffset

    def __getbuffer__(self, Py_buffer* view, int flags):
        # We always provide a writable, C-contiguous direct buffer.
        #
        # For examples of __getbuffer__ implementations see e.g.:
        # http://stackoverflow.com/questions/10465091/assembling-a-cython-memoryview-from-numpy-arrays
        # https://github.com/cython/cython/blob/master/Cython/Utility/MemoryView.pyx
        # https://github.com/cython/cython/blob/master/Cython/Includes/numpy/__init__.pxd#L194
        # https://github.com/cython/cython/blob/master/Cython/Utility/Buffer.c
        cdef bint isCContiguousOk = ((flags == PyBUF_SIMPLE) or
                                     flags & (PyBUF_C_CONTIGUOUS |
                                              PyBUF_ANY_CONTIGUOUS)
                                     )
        if not isCContiguousOk:
            raise ValueError("Persistent buffers are C-contiguous; you "
                             "requested a non-C-contiguous buffer (flags={})."
                             .format(hex(flags))
                             )
        cdef CBuffer *cBuffer = self.getP2IS()

        if flags & PyBUF_FORMAT:
            assert cBuffer.o2format != 0
            view.format = <char*> self.ptype.offset2Address(cBuffer.o2format)
        else:
            view.format = NULL

        LOG.debug("__getbuffer__ {}".format(cBuffer.o2format))

        view.readonly = 0
        view.len = cBuffer.len
        view.ndim = cBuffer.ndim
        view.itemsize = cBuffer.itemsize
        view.buf = self.ptype.offset2Address(cBuffer.o2buf)
        view.shape   = <Py_ssize_t*> self.ptype.offset2Address(cBuffer.o2shape)
        view.strides = \
            <Py_ssize_t*> self.ptype.offset2Address(cBuffer.o2strides)
        view.suboffsets = NULL
        view.internal = NULL
        view.obj = self

    def __releasebuffer__(self, Py_buffer* info):
        LOG.debug("__releasebuffer__")
        # This method is not needed; __getbuffer__() never allocates memory,
        # so there is no need to release anything
        pass

# This property will be used when reconstructor is implemented:
#     property contents:
#         def __get__(self):
#             return self.getValue()
cdef class Buffer(TypeDescriptor):
    meta = BufferMeta
    proxyClass = PBuffer
    minNumberOfParameters = 0
    maxNumberOfParameters = 0

################## BindingRules for persistent buffers #####################
# Will be implemented with the reconstructor
# cdef class BufferContents(BindingRule):
#     """ Bind the contents of a node to the name of the variable.
#     """
#     cdef:
#         BindingRule bufferBindingRule
#
#     def __init__(self, BindingRule bufferBindingRule, bint shortCut=False):
#         BindingRule.__init__(self, bufferBindingRule, shortCut=shortCut)
#         self.bufferBindingRule = bufferBindingRule
#
#     cdef getAll(self, query, QueryContext result):
#         cdef PBuffer buffer = result.getattr(self.bufferBindingRule.name)
#         try:
#             result.setattr(self.name, buffer.getValue() )
#         except Exception as e:
#             e.args = e.args[0] + (" while accessing the contents of {0} in "
#                            "bindingRule '{1}'".format( node, self.name)),
#             raise
#         self.getAllRecursively(query, result)
