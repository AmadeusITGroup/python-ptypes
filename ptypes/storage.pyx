# cython: profile=False

from libc.string cimport memcpy, memcmp, memset

import logging
LOG = logging.getLogger(__name__)

from cPickle import dumps, loads
from math import pow, log as logarithm
from os import SEEK_SET, O_CREAT, O_RDWR
from types import ModuleType
from collections import namedtuple
from time import strptime, mktime
import os
import threading
import gc


cdef class PList


class DbFullException(Exception):
    pass


class RedoFullException(Exception):
    pass

cdef class Persistent(object):
    """ Base class for all the proxy classes for persistent objects.
    """

    def __repr__(self):
        return ("<persistent {0} object @offset {1}>"
                .format(self.ptype.__name__, hex(self.offset))
                )

    def __hash__(self, ):
        return self.offset

    def __richcmp__(Persistent self, other, int op):
        return bool(self.richcmp(other, op))

    property id:
        """ Read-only property giving a tuple uniquely identifies the object.
        """

        def __get__(self):
            return id(self.storage), self.offset

    def isSameAs(Persistent self, Persistent other):
        """ Compare the identity of :class:`Persistent` instances.

        Note that the ``is`` operator compares the identity of the proxy
        objects, not that of the persistent objects they refer to.

        .. py:function:: isSameAs(self, other)

        :param Persistent self: proxy for a persistent object
        :param Persistent other: proxy for another persistent object
        :return: ``True`` if ``self`` refers to the same persistent object as
                    ``other``, otherwise ``False``.
        """
        return self.offset == other.offset and self.storage is other.storage

    cdef int richcmp(Persistent self, other, int op) except? -123:
        raise NotImplementedError()

    cdef store(Persistent self, void *target):
        """ Store self to target.

            Stores by reference or by value (as the type of self dictates).
        """
        raise NotImplementedError()

    cdef revive(Persistent p):
        pass

############################# Assignment By Value ########################

cdef Offset resolveNoOp(PersistentMeta ptype, Offset offset) except -1:
    return offset

cdef class AssignedByValue(Persistent):
    # p2InternalStructure points at a persistent object embedded inside
    # another persistent object

    cdef store(AssignedByValue self, void *target):
        # copies bytes from the value
        memcpy(target, self.p2InternalStructure, self.ptype.assignmentSize)

    # Works only with persistent values. Can be specialized in derived
    # classes for specific types. In the overrider call this if
    # other is persistent, otherwise use the special code
    cdef int richcmp(AssignedByValue self, other, int op) except? -123:
        assert other is not None
        cdef Persistent pother = <Persistent?>other
        cdef int doesDiffer
        if self.ptype == pother.ptype:
            doesDiffer = memcmp(self.p2InternalStructure,
                                pother.p2InternalStructure,
                                self.ptype.assignmentSize)
        else:
            doesDiffer = 1
        if op==2:
            return doesDiffer == 0
        if op==3:
            return doesDiffer != 0
        raise TypeError('{0} does not define a sort order!'.format(self.ptype))

############################# Assignment By Reference ####################

cdef Offset resolveReference(PersistentMeta ptype, Offset offset) except -1:
    return (<Offset*>(ptype.storage.baseAddress + offset))[0]

cdef class AssignedByReference(Persistent):
    # p2InternalStructure points at a stand-alone object on the heap
    cdef store(AssignedByReference self, void *target):
        # store the offset to the value
        (<Offset*>target)[0] = (self.p2InternalStructure -
                                self.storage.baseAddress)

    # works only with persistent values. Can be specialized in derived
    # classes for specific types.
    # In the overrider call this if other is persistent, otherwise use the
    # special code
    cdef int richcmp(AssignedByReference self, other, int op) except? -123:
        cdef:
            Persistent pother
            int doesDiffer
        if other is None:
            doesDiffer = 1
        else:
            pother = <Persistent?>other
            if self.ptype == pother.ptype:
                doesDiffer = self.offset != other.offset
            else:
                doesDiffer = 1
        if op==2:
            return doesDiffer == 0
        if op==3:
            return doesDiffer != 0
        raise TypeError('{0} does not define a sort order!'.format(self.ptype))

############################# PersistentMeta #################################

cdef class PersistentMeta(type):
    """ Abstract base meta class for all persistent types.
    """
    @classmethod
    def _typedef(PersistentMeta meta, Storage storage, str className,
                type proxyClass, *args):
        """ Create and initialize a new persistent type.

        This is a non-public classmethod of :class:`PersistentMeta` and 
        derived classes.

        :param meta: This type object must be the one representing
                :class:`PersistentMeta` or another class derived from
                it. (This parameter is normally filled in with the meta-class 
                of the class the method is invoked on.) The new persistent type is
                created using this type object as its meta-class.

        @param storage:
        @param className: This will be the name of the new type.
        @param proxyClass: The new persistent type will be a
                subclass of this class.

        @return: A properly initialised PersistentMeta instance
                representing the newly created persistent type.
        """
        cdef PersistentMeta ptype = meta.__new__(meta, className,
                                                 (proxyClass,),
                                                 dict(__metaclass__=meta)
                                                 )
        meta.__init__(ptype, storage, className, proxyClass, *args)
        LOG.debug('Created {ptype} from meta-class {meta} using proxy'
                  ' {proxyClass} with arguments {args}'
                  .format(ptype=ptype, meta=meta, proxyClass=proxyClass,
                          args=args)
                  )
        return ptype

    # This method is called to initialise an instance of this meta-class
    # when a new persistent type has just been created
    def __init__(PersistentMeta ptype, Storage storage, str className,
                 type proxyClass, int allocationSize):
        """ Initialize the ptype
        """
        super(PersistentMeta, ptype).__init__(className, (), {})
        ptype.__name__   = className
        ptype.storage = storage
        ptype.proxyClass = proxyClass
        ptype.allocationSize = allocationSize
        if ptype.isAssignedByValue():
            ptype.assignmentSize = allocationSize
            ptype.resolve = resolveNoOp
        else:
            ptype.assignmentSize = sizeof(Offset)
            ptype.resolve = resolveReference

        if not ptype.__name__.startswith('__'):
            storage.registerType(ptype)

    # This method is executed when the function call operator is applied to an
    # instance of this meta-class (which in fact represents a persistent type),
    # here referred to as "ptype"
    def __call__(PersistentMeta ptype, *args, **kwargs):
        """ Create an instance of the ptype.
        """
        if ptype.isAssignedByValue():
            raise TypeError(
                '{ptype} exhibits store-by-value semantics and therefore can '
                'only be instantiated inside a container (e.g. in Structure)'
                .format(ptype=ptype))
        # always by ref
        cdef Persistent self = ptype.createProxy(allocateStorage(ptype))
        ptype.proxyClass.__init__(self, *args, **kwargs)
        return self

    cdef Persistent createProxy(PersistentMeta ptype, Offset offset):
        cdef Persistent self
        if offset:
            if ptype.storage.realFileSize < offset:
                print(
                    "Corruption: offset {offset} is outside the mapped memory!"
                    " - Aborting.".format(offset=offset))
                abort()
            self = ptype.__new__(ptype)
            self.p2InternalStructure =  ptype.offset2Address(offset)
            self.ptype = ptype
            self.storage = ptype.storage
            self.offset = offset
#             LOG.debug('createProxy: {0} {1} ==> {2}'
#                        .format(ptype.proxyClass, offset, repr(self)))
            self.revive()
            return self
        else:
            return None

    def reduce(self):
        return '_typedef', self.__name__, self.__class__, self.proxyClass

    cdef assign(PersistentMeta ptype, void *target, source, ):
        """ Assign source to target converting to persistent if needed.

            If ``source`` is a persistent type then it must be an instance of
            the type represented by ``ptype``. If it is a volatile Python value
            and the type represented by ``ptype`` is assigned by value, then
            the assignment is performed via the ``contents`` descriptor of the
            type. For types assigned by reference a new instance of the type is
            created and ``source`` is passed to the constructor, unless it is
            ``None``, in which case the reference is set to the persistent
            representation of ``None``.
        """
        if isinstance(source, Persistent):
            ptype.assertType(source)
            (<Persistent>source).store(target)
        elif ptype.isAssignedByValue():
            ptype.resolveAndCreateProxyFA(target).contents = source
        elif source is None:
            (<Offset*>target)[0] = 0
        else:
            (<Persistent>ptype(source)).store(target)

    cdef void clear(PersistentMeta ptype, Offset o2Target):
        memset(ptype.storage.baseAddress + o2Target, 0, ptype.assignmentSize)

    cdef int isAssignedByValue(PersistentMeta ptype) except? -123:
        cdef:
            bint isByValue = issubclass(ptype.proxyClass, AssignedByValue)
            bint raiseTypeError=False
        if isByValue:
            raiseTypeError = issubclass(ptype.proxyClass, AssignedByReference)
        else:
            raiseTypeError = not issubclass(
                ptype.proxyClass, AssignedByReference)
        if raiseTypeError:
            raise TypeError("The proxyClass {0} must be a subclass of  either "
                            "'AssignedByValue' or 'AssignedByReference'."
                            .format(ptype.proxyClass))
        return isByValue

    cdef assertType(PersistentMeta ptype, Persistent persistent):
        if persistent:
            if persistent.ptype.storage is not ptype.storage:
                raise ValueError(
                    "Expected a persistent object in {0}, not in {1}!"
                    .format(ptype.storage, persistent.ptype.storage)
                )
            if not issubclass(persistent.ptype, ptype):
                raise TypeError(
                    "Expected {0}, found {1}".format(ptype, persistent.ptype))

    def __repr__(ptype):
        return "<persistent class '{0}'>".format(ptype.__name__)


############################# Type Descriptor #################################

cdef class TypeDescriptor(object):
    minNumberOfParameters=None
    maxNumberOfParameters=None

    def __init__(TypeDescriptor self, str className=None):
        if className is None:
            className = self.__class__.__name__
        self.className = className
        self.typeParameters = tuple()

    def __getitem__(TypeDescriptor self, typeParameters):
        if not isinstance(typeParameters, tuple):
            typeParameters = typeParameters,
        if self.typeParameters:
            raise ValueError("The parameters of type {self.className} are "
                             "already set to {self.typeParameters}"
                             .format(self=self))
        self.verifyTypeParameters(typeParameters)
        self.typeParameters = typeParameters
        return self

    def verifyTypeParameters(self, tuple typeParameters):
        if self.minNumberOfParameters is None and typeParameters:
            raise TypeError("The type {self.className} does not accept "
                            "parameters!".format(self=self))

        if self.minNumberOfParameters and (len(typeParameters) <
                                           self.minNumberOfParameters):
            raise TypeError("Type {self.className} must have at least "
                            "{self.minNumberOfParameters} parameter(s), "
                            "found {typeParameters}".format(
                                self=self, typeParameters=typeParameters)
                            )
        if self.maxNumberOfParameters and (len(typeParameters) >
                                           self.maxNumberOfParameters):
            raise TypeError("Type {self.className} must have at most "
                            "{self.maxNumberOfParameters} parameter(s), "
                            "found {typeParameters}".format(
                                self=self, typeParameters=typeParameters)
                            )

############################## Int  ######################################

cdef class IntMeta(PersistentMeta):

    def __init__(IntMeta ptype,
                 Storage storage,
                 str className,
                 type proxyClass,
                 ):
        assert issubclass(proxyClass, PInt), proxyClass
        PersistentMeta.__init__(ptype, storage, className, proxyClass,
                                sizeof(long))

cdef class PInt(AssignedByValue):

    cdef inline long *getP2IS(self):
        return <long *>self.p2InternalStructure

    def __str__(self):
        return str(self.getP2IS()[0])

    def __repr__(self):
        return ("<persistent {0} object '{1}' @offset {2}>"
                .format(self.ptype.__name__, self.getP2IS()[0],
                        hex(self.offset)))

    property contents:
        def __get__(self):
            return self.getP2IS()[0]

        def __set__(self, long value):
            self.getP2IS()[0] = value

    # The offset is not OK here: it must match that of the volatile object!
    def __hash__(self, ):
        return hash(self.getP2IS()[0])

    cdef int richcmp(PInt self, other, int op) except? -123:
        cdef long otherValue
        if isinstance(other, PInt):
            otherValue = (<PInt> other).getP2IS()[0]
        else:
            if isinstance(other, int):
                otherValue = <long?>other
            else:
                if op==2:
                    return False  # self == other
                if op==3:
                    return True  # self != other
                raise TypeError(
                    '{0} does not define a sort order for {1}!'
                    .format(self.ptype, other)
                )
        if op==0:
            return self.getP2IS()[0] <  otherValue  # self  < other
        if op==1:
            return self.getP2IS()[0] <= otherValue  # self <= other
        if op==2:
            return self.getP2IS()[0] == otherValue  # self == other
        if op==3:
            return self.getP2IS()[0] != otherValue  # self != other
        if op==4:
            return self.getP2IS()[0] >  otherValue  # self  > other
        if op==5:
            return self.getP2IS()[0] >= otherValue  # self >= other
        assert False, "Unknown operation code '{0}".format(op)

    cpdef inc(self):
        self.getP2IS()[0] += 1

    cpdef add(self, long value):
        self.getP2IS()[0] += value

    cpdef setBit(self, int numberOfBit):
        self.getP2IS()[0] |= 1 << numberOfBit

    cpdef clearBit(self, int numberOfBit):
        self.getP2IS()[0] &= ~(1 << numberOfBit)

    cpdef int testBit(self, int numberOfBit):
        return self.getP2IS()[0] & (1 << numberOfBit)

cdef class Int(TypeDescriptor):
    meta = IntMeta
    proxyClass = PInt

############################## Float  ######################################

cdef class FloatMeta(PersistentMeta):

    def __init__(self,
                 Storage storage,
                 className,
                 proxyClass=None,
                 ):
        if proxyClass is None:
            proxyClass = PFloat
        assert issubclass(proxyClass, PFloat), proxyClass
        PersistentMeta.__init__(
            self, storage, className, proxyClass, sizeof(double))


cdef class PFloat(AssignedByValue):

    cdef inline double *getP2IS(self):
        return <double *>self.p2InternalStructure

    def __str__(self):
        return str(self.getP2IS()[0])

    def __repr__(self):
        return ("<persistent {0} object '{1}' @offset {2}>"
                .format(self.ptype.__name__, self.getP2IS()[0],
                        hex(self.offset)))

    property contents:
        def __get__(self):
            return self.getP2IS()[0]

        def __set__(self, double value):
            self.getP2IS()[0] = value

    # The offset is not OK here: it must match that of the volatile object!
    def __hash__(self, ):
        return hash(self.getP2IS()[0])

    cdef int richcmp(PFloat self, other, int op) except? -123:
        cdef double otherValue
        if isinstance(other, PFloat):
            otherValue = (<PFloat> other).getP2IS()[0]
        else:
            if isinstance(other, float):
                otherValue = <double?>other
            else:
                if op==2:
                    return False  # self == other
                if op==3:
                    return True  # self != other
                raise TypeError(
                    '{0} does not define a sort order for {1}!'
                    .format(self.ptype, other))
        if op==0:
            return self.getP2IS()[0] <  otherValue  # self  < other
        if op==1:
            return self.getP2IS()[0] <= otherValue  # self <= other
        if op==2:
            return self.getP2IS()[0] == otherValue  # self == other
        if op==3:
            return self.getP2IS()[0] != otherValue  # self != other
        if op==4:
            return self.getP2IS()[0] >  otherValue  # self  > other
        if op==5:
            return self.getP2IS()[0] >= otherValue  # self >= other
        assert False, "Unknown operation code '{0}".format(op)

    cpdef add(self, double value):
        self.getP2IS()[0] += value

cdef class Float(TypeDescriptor):
    meta = FloatMeta
    proxyClass = PFloat

############################## String ######################################

cdef class StringMeta(PersistentMeta):

    def __call__(StringMeta ptype, object volatileString):
        """ Create an instance of the type ptype represents.
        """
        cdef:
            int size = len(volatileString)
            PString self = ptype.createProxy(ptype.storage
                                             .allocate(sizeof(int) + size))
        (<int*>self.p2InternalStructure)[0] = size
        memcpy(self.getCharPtr(), <char *?>volatileString, size)
        return self

    def __init__(StringMeta ptype,
                 Storage storage,
                 className,
                 proxyClass=None,
                 ):
        if proxyClass is None:
            proxyClass = PString
        assert issubclass(proxyClass, PString), proxyClass
        # allocationSize is not used, no need to initialize it
        PersistentMeta.__init__(ptype, storage, className, proxyClass, 0)


cdef class PString(AssignedByReference):

    def __str__(self):
        return self.contents

    def __repr__(self):
        return ("<persistent {0} object {1} @offset {2}>"
                .format(self.ptype.__name__,
                        repr(self.getString()[:self.getSize()]),
                        hex(self.offset)
                        )
                )

    property contents:
        def __get__(self):
            return self.getString()

    # The offset is not OK here: it must match that of the volatile object!
    def __hash__(self, ):
        return hash(self.getString())

    cdef int richcmp(PString self, other, int op) except? -123:
        cdef:
            char *selfValue
            char *otherValue
            int otherSize, doesDiffer
        selfValue = self.getCharPtr()
        if isinstance(other, PString):
            otherSize  = (<PString> other).getSize()
            otherValue = (<PString> other).getCharPtr()
        else:
            if isinstance(other, str):
                otherSize  = len(<str> other)
                otherValue = <char *>other
            else:
                if op==2:
                    return False  # self == other
                if op==3:
                    return True  # self != other
                raise TypeError(
                    '{0} does not define a sort order for {1}!'
                    .format(self.ptype, other)
                )
        doesDiffer = memcmp(
            selfValue, otherValue, min(self.getSize(), otherSize))
        if not doesDiffer:
            doesDiffer =  self.getSize() - otherSize
        if op==0:
            return doesDiffer <  0  # self  < other
        if op==1:
            return doesDiffer <= 0  # self <= other
        if op==2:
            return doesDiffer == 0  # self == other
        if op==3:
            return doesDiffer != 0  # self != other
        if op==4:
            return doesDiffer >  0  # self  > other
        if op==5:
            return doesDiffer >= 0  # self >= other
        assert False, "Unknown operation code '{0}".format(op)

cdef class __String(TypeDescriptor):
    meta = StringMeta
    proxyClass = PString


############################## HashEntry ######################################
cdef:
    struct CHashTable:
        unsigned long _capacity, _used,
        Offset        _mask, o2EntryTable

cdef class HashEntryMeta(PersistentMeta):
    def __init__(self,
                 Storage          storage,
                 str              className,
                 type             proxyClass,
                 PersistentMeta   keyClass,
                 PersistentMeta   valueClass=None,
                 ):
        assert issubclass(proxyClass, PHashEntry), proxyClass
        self.o2Key   = sizeof(CHashEntry)
        self.o2Value = self.o2Key + keyClass.assignmentSize
        PersistentMeta.__init__(self, storage, className, proxyClass,
                                self.o2Value +
                                (valueClass.assignmentSize if valueClass
                                 else 0)
                                )
        self.keyClass   = keyClass
        self.valueClass = valueClass
        # do these 2 have the same storage as the entrymeta?

    def reduce(self):
        assert False, ("The name of HashEntryMeta instances must start with "
                       "'__' in order to prevent pickling them!")


cdef class PHashEntry(AssignedByValue):
    pass

############################## HashTable ######################################

cdef class HashTableMeta(PersistentMeta):

    @classmethod
    def _typedef(PersistentMeta meta, Storage storage, str className,
                type proxyClass, PersistentMeta keyClass,
                PersistentMeta valueClass=None):
        if keyClass is None:
            raise TypeError("The type parameter specifying the type of keys "
                            "cannot be {0}" .format(keyClass)
                            )
        cdef:
            str entryName =  (
                ('__{keyClass.__name__}And{valueClass.__name__}AsHashEntry'
                 .format(keyClass=keyClass, valueClass=valueClass)
                 ) if valueClass else (
                    '__{keyClass.__name__}AsHashEntry'
                    .format(keyClass=keyClass)
                )
            )
            PersistentMeta entryClass = HashEntryMeta._typedef(storage,
                                                              entryName,
                                                              PHashEntry,
                                                              keyClass,
                                                              valueClass)

        return super(HashTableMeta, meta)._typedef(storage, className,
                                                  proxyClass, entryClass)

    def __init__(self,
                 Storage       storage,
                 str              className,
                 type             proxyClass,
                 HashEntryMeta    hashEntryClass
                 ):
        assert issubclass(proxyClass, PHashTable), proxyClass
        PersistentMeta.__init__(
            self, storage, className, proxyClass, sizeof(CHashTable))
        self.hashEntryClass =  hashEntryClass

    def reduce(self):
        return ('_typedef', self.__name__, self.__class__, self.proxyClass,
                ('PersistentMeta',
                 None if self.hashEntryClass.keyClass is None
                 else self.hashEntryClass.keyClass.__name__),
                ('PersistentMeta',
                 None if self.hashEntryClass.valueClass is None
                 else self.hashEntryClass.valueClass.__name__),
                )


cdef class PHashTable(AssignedByReference):

    cdef revive(self):
        self.hashEntryClass = (<HashTableMeta>self.ptype).hashEntryClass
        self.keyClass = self.hashEntryClass.keyClass
        self.valueClass =  self.hashEntryClass.valueClass
        self.o2Key =  self.hashEntryClass.o2Key
        self.o2Value =  self.hashEntryClass.o2Value

    def __init__(PHashTable self, unsigned long size, ):
        assert size > 0, 'The size of a HashTable cannot be {size}.'.format(
            size=size)
        actualSize = size*3/2
        actualSize = int(pow(2, int(logarithm(actualSize)/logarithm(2))+1))
        self.getP2IS()._capacity = 9*actualSize/10
        self.getP2IS()._mask = actualSize-1
        self.getP2IS()._used = 0
        cdef unsigned long hashTableSize = (actualSize *
                                            self.hashEntryClass.assignmentSize)
        self.getP2IS().o2EntryTable = self.storage.allocate(hashTableSize)
        memset(self.storage.baseAddress +
               self.getP2IS().o2EntryTable, 0, hashTableSize)
        LOG.debug("Created new HashTable  {4} of type '{0}', "
                  "requested_size={1} actual size={2} allowed capacity={3}."
                  .format(self.ptype.__name__, size, actualSize,
                          self.getP2IS()._capacity, self)
                  )

    cdef CHashEntry* _findEntry(self, object key) except NULL:
        cdef unsigned long i, perturb, h
        h = <unsigned long>hash(key)
        i = h & self.getP2IS()._mask
        perturb = h
        cdef:
            CHashEntry* p2Entry = self.getP2Entry(i)
            Persistent foundKey
        while True:
            if not p2Entry.isUsed:
                break
            foundKey = self.getKey(p2Entry)
            if foundKey is None:
                if key is None:
                    break
            else:
                if foundKey.richcmp(key, 2):
                    break
            perturb >>= 5
            i = (i << 2) + i + perturb + 1
            p2Entry = self.getP2Entry(i & self.getP2IS()._mask)
        return p2Entry

    def __getitem__(self, key):
        """ Get they value associated with key.

            @return: the persistent object associated with the key as value

            If the value class of the hash table is None (i.e. applying the
            operation on a set), then the persistent version of the passed in
            key is returned.

            @raise KeyError: the key is unknown
        """
        cdef CHashEntry* p2Entry = self._findEntry(key)
        if not p2Entry.isUsed:
            self.missing(p2Entry, key)
        if self.hashEntryClass.valueClass:
            return self.getValue(p2Entry)
        else:
            return self.getKey(p2Entry)

    cdef missing(self, CHashEntry* p2Entry, key):
        raise KeyError(key)

    def __setitem__(self, key, value):
        """ Set they value associated with key

            If the value class of the hash table is None (i.e. applying the
            operation on a set), then value is silently ignored.
        """
        cdef CHashEntry* p2Entry = self._findEntry(key)
        self.setKey(p2Entry, key)
        if self.hashEntryClass.valueClass:
            self.setValue(p2Entry, value)

    cpdef Persistent get(self, object key, value=None):
        """ Return the matching persistent version of a volatile key.

            If the hash table does not have a matching persistent key, then
            the volatile key is persisted according to the assignemnt rules of
            the key class. If the key is persisted in the current invocation,
            then the optional value is also associated to the key, provided the
            value class of the hash table is not ``None`` (i.e. the hash table
            on which ``get()`` was invoked is a dictionary). If the value class
            is ``None`` (the hash table is a set), then the value is always
            silently ignored. If the hash table already contained a matching
            persistent key before the invocation, then the value associated
            with the key is not altered.

            @return: The matching persistent key.
        """
        cdef CHashEntry* p2Entry = self._findEntry(key)
        if not p2Entry.isUsed:
            self.setKey(p2Entry, key)
            if self.hashEntryClass.valueClass:
                self.setValue(p2Entry, value)
        return self.getKey(p2Entry)

    def iterkeys(self):
        cdef:
            unsigned long i
            CHashEntry* p2Entry
        for i in range(0, self.getP2IS()._mask+1):
            p2Entry = self.getP2Entry(i)
            if p2Entry.isUsed:
                yield self.getKey(p2Entry)

    def itervalues(self):
        cdef:
            unsigned long i
            CHashEntry* p2Entry
        if self.hashEntryClass.valueClass:
            for i in range(0, self.getP2IS()._mask+1):
                p2Entry = self.getP2Entry(i)
                if p2Entry.isUsed:
                    yield self.getValue(p2Entry)
        else:
            raise TypeError('Cannot iterate over the values: no value class '
                            'is defined. (Is this not a Set?)')

    def iteritems(self):
        cdef:
            unsigned long i
            CHashEntry* p2Entry
        if self.hashEntryClass.valueClass:
            for i in range(0, self.getP2IS()._mask+1):
                p2Entry = self.getP2Entry(i)
                if p2Entry.isUsed:
                    yield (self.getKey(p2Entry), self.getValue(p2Entry))
        else:
            raise TypeError('Cannot iterate over the items: no value class '
                            'is defined. (Is this not a Set?)')

    cdef incrementUsed(self):
        if self.getP2IS()._used >= self.getP2IS()._capacity:
            raise DbFullException("HashTable of type '{0}' is full, current "
                                  "capacity is {1}."
                                  .format(self.ptype.__name__,
                                          self.getP2IS()._capacity)
                                  )
        self.getP2IS()._used += 1

    property numberOfUsedEntries:
        def __get__(self):
            return self.getP2IS()._used

    property capacity:
        def __get__(self):
            return self.getP2IS()._capacity

cdef class PDefaultHashTable(PHashTable):

    cdef missing(self, CHashEntry* p2Entry, key):
        self.incrementUsed()
        p2Entry.isUsed = 1
        self.setKey(p2Entry, key)
        value = self.hashEntryClass.valueClass()
        self.setValue(p2Entry, value)


############################  Set #############################
cdef class Set(TypeDescriptor):
    meta = HashTableMeta
    proxyClass = PHashTable
    minNumberOfParameters=1
    maxNumberOfParameters=1


############################  Dictionary #############################
cdef class Dict(TypeDescriptor):
    meta = HashTableMeta
    proxyClass = PHashTable
    minNumberOfParameters=2
    maxNumberOfParameters=2


cdef class DefaultDict(Dict):
    proxyClass = PDefaultHashTable


############################## List ######################################
cdef class ListMeta(PersistentMeta):

    @classmethod
    def _typedef(PersistentMeta meta, Storage storage, str className,
                type proxyClass, PersistentMeta valueClass):
        if valueClass is None:
            raise TypeError("The type parameter specifying the type of list "
                            "elements cannot be None.")
        return super(ListMeta, meta)._typedef(storage, className, proxyClass,
                                             valueClass)

    def __init__(self,
                 Storage       storage,
                 str              className,
                 type             proxyClass,
                 PersistentMeta   valueClass,
                 ):
        assert issubclass(proxyClass, PList), proxyClass
        PersistentMeta.__init__(
            self, storage, className, proxyClass, sizeof(CList))
        self.valueClass  = valueClass
        self.o2Value = sizeof(CListEntry)

    def reduce(self):
        return ('_typedef', self.__name__, self.__class__, self.proxyClass,
                ('PersistentMeta', self.valueClass.__name__),
                )


cdef class PList(AssignedByReference):

    def __init__(self):
        self.getP2IS().o2FirstEntry = self.getP2IS().o2LastEntry = 0

    cdef CListEntry *newEntry(self, value, Offset* o2NewEntry):
        cdef PersistentMeta valueClass = (<ListMeta>(self.ptype)).valueClass
        o2NewEntry[0] = self.storage.allocate(
            sizeof(CListEntry)  + valueClass.assignmentSize)
        cdef CListEntry *p2NewEntry = <CListEntry *>(self.storage.baseAddress +
                                                     o2NewEntry[0])
        valueClass.assign((<void*>p2NewEntry) +
                          (<ListMeta>(self.ptype)).o2Value,
                          value
                          )
        return p2NewEntry

    cpdef insert(PList self, object value):
        cdef:
            Offset o2NewEntry
            CListEntry   *p2NewEntry = self.newEntry(value, &o2NewEntry)
        p2NewEntry.o2NextEntry = self.getP2IS().o2FirstEntry
        self.getP2IS().o2FirstEntry = o2NewEntry
        if self.getP2IS().o2LastEntry == 0:
            self.getP2IS().o2LastEntry = self.getP2IS().o2FirstEntry

    cpdef append(PList self, object value):
        cdef:
            Offset o2NewEntry
            CListEntry   *p2NewEntry = self.newEntry(value, &o2NewEntry)
        p2NewEntry.o2NextEntry = 0
        if self.getP2IS().o2LastEntry == 0:
            self.getP2IS().o2FirstEntry = o2NewEntry
        else:
            # Caveat!
            # http://stackoverflow.com/questions/11498441/what-is-this-kind-of-assignment-in-python-called-a-b-true
            p2LastEntry =  <CListEntry *>(self.storage.baseAddress +
                                          self.getP2IS().o2LastEntry)
            p2LastEntry.o2NextEntry = o2NewEntry
        self.getP2IS().o2LastEntry = o2NewEntry

    def __iter__(self):
        cdef:
            Offset o2Entry = self.getP2IS().o2FirstEntry
            CListEntry   *p2Entry
            PersistentMeta valueClass = (<ListMeta>(self.ptype)).valueClass
        while o2Entry:
            p2Entry = <CListEntry *>(self.storage.baseAddress + o2Entry)
            # LOG.info(p2Entry.o2 Value)
            yield valueClass.resolveAndCreateProxyFA(p2Entry + 1)
            o2Entry = p2Entry.o2NextEntry

cdef class List(TypeDescriptor):
    meta = ListMeta
    proxyClass = PList
    minNumberOfParameters=1
    maxNumberOfParameters=1

############################## Structure ######################################
threadLocal = threading.local()
cdef class StructureMeta(PersistentMeta):

    def __init__(ptype, className, bases, dict attribute_dict):
#         assert bases==(Structure,), bases  # no base classes supported yet
        cdef Storage storage = getattr(threadLocal, 'currentStorage', None)
        if storage is None:
            raise Exception("Types with {ptype.__class__.__name__} as "
                            "__metaclass__ must be defined in the "
                            "populateSchema() method of Storage subclasses!"
                            .format(ptype=ptype)
                            )
        PersistentMeta.__init__(ptype, storage, className, PStructure, 0)
        ptype.fields = list()
        ptype.pfields = dict()
        for fieldName, fieldType in sorted(attribute_dict.items()):
            if isinstance(fieldType, PersistentMeta):
                ptype.addField(fieldName, fieldType)
        ptype.NamedTupleClass = namedtuple(className, ptype.pfields.keys())
        LOG.debug('Created {ptype} from meta-class {meta} using proxy '
                  '{proxyClass} allocationSize {allocationSize}'
                  .format(ptype=ptype, meta=type(ptype), proxyClass=PStructure,
                          allocationSize=ptype.allocationSize)
                  )

    cdef addField(StructureMeta ptype, name, PersistentMeta fieldType):
        ptype.fields.append((name, fieldType.__name__))
        cdef pfield = PField(ptype.allocationSize, name, fieldType)
        ptype.pfields[name] = pfield
        setattr(ptype, name, pfield)
        ptype.allocationSize += fieldType.assignmentSize
        LOG.debug(
            'Added {field} to {ptype}' .format(field=pfield, ptype=ptype))

    def reduce(ptype):
        d = dict(ptype.__dict__)
        for name in ['__metaclass__', '__dict__', '__weakref__', '__module__',
                     'storage',]:
            d.pop(name, None)
        for k, v in d.items():
            if isinstance(v, PField):
                del d[k]
        bases = list()
        for base in ptype.__bases__:
            if type(base) is StructureMeta:
                base = ('persistentBase', base.__name__)
            else: 
                base = ('volatileBase', base)
            bases.append(base)
        return ('StructureMeta', ptype.__name__, bases, d, ptype.fields)


cdef class PStructure(AssignedByReference):
    """ A structure is like a mutable named tuple.

        Structures are usable as hash keys (they are hashable), but prepare
        for surprises if you do so and change the contents of the structure
        after initialisation.

        Structures lack the 'greater than / less than' relational operators,
        so they are not usable as keys in skip lists.

        Structures can be compared for (non-)equality. They are
        compared field-by-field, accessing via ``getattr()``.
        Extra fields on the compared-to-object are ignored.

        Accessing the ``contents`` attribute of a structure instance will
        return a named tuple. Assigning to the attribute will set the
        contents of the structure to the assigned value,
        which must have at least the attributes the structure has fields.
    """
    def __init__(PStructure self, value=None, **kwargs):
        cdef PField pfield
        for pfield in (<StructureMeta>self.ptype).pfields.values():
            pfield.ptype.clear(self.offset + pfield.offset)
        if value is not None:
            self.set(value)
        for k, v in kwargs.items():
            setattr(self, k, v)

    # The offset is not OK here: it must match that of the volatile object!
    def __hash__(self, ):
        return hash(self.get())

    cdef int richcmp(PStructure self, other, int op) except? -123:
        cdef:
            Persistent value
            PField pfield
            bint doesDiffer
        if other is None:
            doesDiffer = True
        else:
            doesDiffer = False
            for pfield in (<StructureMeta>self.ptype).pfields.values():
                value = pfield.get(self)
                try:
                    otherValue = getattr(other, pfield.name)
                except AttributeError:
                    doesDiffer = True
                    break
                else:
                    if value is None:
                        if otherValue is not None:
                            doesDiffer = True
                            break
                    else:
                        if value.richcmp(otherValue, 3):
                            doesDiffer = True
                            break
        if op==2:
            return not doesDiffer
        if op==3:
            return doesDiffer
        raise TypeError('{0} does not define a sort order!'.format(self.ptype))

    cdef get(PStructure self):
        cdef:
            PField  pfield
            dict    pfields = (<StructureMeta>self.ptype).pfields
            list    values = list()
            type    NamedTupleClass = (<StructureMeta>
                                       self.ptype).NamedTupleClass
        for fieldName in NamedTupleClass._fields:
            pfield = pfields[fieldName]
            values.append(pfield.get(self))
        return NamedTupleClass(*values)

    cdef set(PStructure self, value):
        cdef:
            PField  pfield
            dict    pfields = (<StructureMeta>self.ptype).pfields
        for pfield in pfields.values():
            pfield.set(self, getattr(value, pfield.name))

    property contents:
        def __get__(PStructure self):
            return self.get()

        def __set__(PStructure self, value):
            self.set(value)

cdef class PField(object):

    def __init__(PField self, int offset, str name, PersistentMeta ptype=None):
        self.offset = offset  # offset into the structure
        self.ptype = ptype
        self.name = name

    def __repr__(self):
        return ('PField({1}, offset={0}, ptype={2})'
                .format(self.offset, self.name, self.ptype))

    property size:
        def __get__(PField self):
            return self.ptype.assignmentSize

    def __get__(PField self, PStructure owner, ownerClass):
        if owner is None:
            return self
        else:
            return self.get(owner)

    cdef Persistent get(PField self, PStructure owner):
        assert owner is not None
        assert owner.storage is self.ptype.storage, (
            owner.storage, self.ptype.storage)
#         LOG.debug( str(('getting', hex(owner.offset), self.offset)) )
        return self.ptype.resolveAndCreateProxy(owner.offset + self.offset)

    def __set__(PField self, PStructure owner, value):
        self.set(owner, value)

    cdef set(PField self, PStructure owner, value):
        assert owner is not None
#         LOG.debug( str(('setting', hex(owner.offset), self.offset, value)) )
        self.ptype.assign(owner.p2InternalStructure + self.offset, value)

############################## Storage ######################################

cdef char *ptypesMagic     = "ptypes-0.5.0"       # Maintained by bumpbersion,
cdef char *ptypesRedoMagic = "redo-ptypes-0.5.0"  # no manual changes please!
DEF lengthOfMagic = 31
DEF numMetadata = 2
DEF PAGESIZE = 4096

cdef extern from "sys/mman.h":
    void *mmap(void *addr, size_t length, int prot, int flags, int fd,
               int offset)
    int munmap(void *addr, size_t length)
    int PROT_READ, PROT_WRITE,
    int MAP_SHARED, MAP_PRIVATE  # flags
    void *MAP_FAILED

    int msync(void *addr, size_t length, int flags)
    int MS_ASYNC, MS_SYNC  # flags

cdef extern from "errno.h":
    int errno

cdef extern from "string.h":
    char *strerror(int errnum)

cdef class MemoryMappedFile(object):

    def __init__(self, str fileName, int numPages=0):
        self.fileName = fileName
        try:
            self.fd = os.open(self.fileName, os.O_RDWR)
        except OSError:
            LOG.debug("Creating new file '{self.fileName}'".format(self=self))
            assert numPages > 0, ('The database cannot have {numPages} pages.'
                                  .format(numPages=self.numPages)
                                  )
            self.isNew = 1
            self.numPages = numPages
            self.realFileSize = self.numPages * PAGESIZE
            self.fd = os.open(self.fileName, O_CREAT | O_RDWR)
            os.lseek(self.fd, self.realFileSize-1, SEEK_SET)
            os.write(self.fd, '\x00')
        else:
            LOG.debug(
                "Opened existing file '{self.fileName}'".format(self=self))
            self.isNew = 0
            self.realFileSize = os.fstat(self.fd).st_size
            self.numPages = int(self.realFileSize / PAGESIZE)
        cdef int myerr=0
        self.baseAddress = mmap(NULL, self.realFileSize, PROT_READ |PROT_WRITE,
                                MAP_SHARED, self.fd, 0)
        if self.baseAddress == MAP_FAILED:
            myerr = errno  # save it, any c-lib call may overwrite it!
            raise Exception('Could not map {self.fileName}: {0}'
                            .format(strerror(myerr), self=self)
                            )
        self.endAddress = self.baseAddress + self.realFileSize
        LOG.debug('Mmapped {self.fileName} memory region {0}-{1}'
                  .format(hex(<unsigned long>self.baseAddress),
                          hex(self.realFileSize), self=self)
                  )
        if self.isNew:
            self._initialize()
        else:
            self._mount()

    cpdef flush(self, bint async=0):
        cdef int myerr=0
        LOG.debug('Msyncing {self.fileName} memory region {0}-{1}'
                  .format(hex(<unsigned long>self.baseAddress),
                          hex(self.realFileSize), self=self)
                  )
        if msync(self.baseAddress, self.realFileSize,
                 MS_ASYNC if async else MS_SYNC):
            myerr = errno  # save it, any c-lib call may overwrite it!
            raise Exception('Could not sync {self.fileName}: {0}'
                            .format(strerror(myerr), self=self)
                            )

    cpdef close(self):
        self.assertNotClosed()
        cdef int myerr=0
        LOG.debug('Unmapping {self.fileName} memory region {0}-{1}'
                  .format(hex(<unsigned long>self.baseAddress),
                          hex(self.realFileSize), self=self)
                  )
        if munmap(self.baseAddress, self.realFileSize):
            myerr = errno
            raise Exception('Could not unmap {self.fileName}: {0}'
                            .format(strerror(myerr), self=self)
                            )
        os.close(self.fd)
        self.baseAddress = NULL

    def __repr__(self):
        return ("<{self.__class__.__name__} '{self.fileName}'>"
                .format(self=self))


cdef struct CRedoFileHeader:
    char magic[lengthOfMagic]

    # offsets to the first trx header and to where the next trx header
    # probably can be written (just a hint, a shortcut to a trx header
    # near to the tail, need to verify if it is really unused,
    # i.e. the length & checksum of the trx header are zeros)
    Offset o2firstTrx, o2Tail

cdef class Redo(MemoryMappedFile):
    cdef:
        CRedoFileHeader       *p2FileHeader
        CTrxHeader            *p2Tail

    def __init__(self, str fileName, int numPages=0):
        MemoryMappedFile.__init__(self, fileName, numPages)
        cdef:
            MD5_CTX md5Context
            MD5_checksum checksum
        self.p2Tail = <CTrxHeader*>(self.baseAddress +
                                    self.p2FileHeader.o2Tail)
        while (self.p2Tail.length != 0 and
               self.p2Tail.length < self.realFileSize
               ):
            MD5_Init(&md5Context)
            MD5_Update(&md5Context, <void*>(self.p2Tail+1), self.p2Tail.length)
            MD5_Final(checksum, &md5Context, )
            if memcmp(self.p2Tail.checksum, checksum, sizeof(MD5_checksum)):
                break
            self.p2Tail = <CTrxHeader *>(<void*>self.p2Tail +
                                         sizeof(CTrxHeader) +
                                         self.p2Tail.length
                                         )

    def _initialize(self):
        LOG.info("Initializing journal '{self.fileName}'".format(self=self))
        assert len(ptypesRedoMagic) < lengthOfMagic
        cdef int j
        self.p2FileHeader = <CRedoFileHeader*>self.baseAddress
        for j in range(len(ptypesRedoMagic)):
            self.p2FileHeader.magic[j] = ptypesRedoMagic[j]
        self.p2FileHeader.o2Tail = self.p2FileHeader.o2firstTrx = sizeof(
            CRedoFileHeader)  # numMetadata*PAGESIZE

    def _mount(self):
        LOG.info(
            "Mounting existing journal '{self.fileName}'".format(self=self))
        self.p2FileHeader = <CRedoFileHeader*>self.baseAddress
        if any(self.p2FileHeader.magic[j] != ptypesRedoMagic[j]
               for j in range(len(ptypesRedoMagic))
               ):
            raise Exception('File {self.fileName} is incompatible with this'
                            'version of ptypes!'.format(self=self)
                            )

    cpdef close(self):
        self.flush()
        self.p2FileHeader.o2Tail = <void*>self.p2Tail - self.baseAddress
        self.flush()

from md5 cimport MD5_checksum, MD5_CTX, MD5_Init, MD5_Update, MD5_Final

cdef struct CTrxHeader:
    # A transaction starts with a trx header, which is followed by a set of
    # redo records with the given total length.
    # It is committed if the checksum is correct (it is filled in after all the
    # redo records).
    # We rely on the "sparse file" mechanism of the kernel to initialize this
    # data structure to zeros.
    unsigned long length
    MD5_checksum checksum

cdef struct CRedoRecordHeader:
    # A redo record consists of a redo record header followed by a body
    # The body has the given length and is opaque; it is copied byte-by-byte
    # to the target offset when the redo is applied.
    Offset offset
    unsigned long length

cdef class Trx(object):
    cdef:
        Storage          storage
        Redo                redo
#         CRedoFileHeader     *p2FileHeader
#         CTrxHeader          *p2TrxHeader
        CRedoRecordHeader   *p2CRedoRecordHeader
        MD5_CTX             md5Context

    def __init__(self, Storage storage, Redo redo):
        self.storage = storage
        self.redo = redo
        redo.assertNotClosed()
#         self.p2FileHeader = redo.p2FileHeader

        self.p2CRedoRecordHeader = (<CRedoRecordHeader*>
                                    (<void*>redo.p2Tail +
                                     sizeof(CRedoRecordHeader)
                                     )
                                    )
        MD5_Init(&self.md5Context)

    cdef save(self, const void *sourceAddress, unsigned long length):
        assert self.redo
        assert self.storage
        if (<void*>self.p2CRedoRecordHeader +
                sizeof(CRedoRecordHeader) +length >= self.redo.endAddress):
            raise RedoFullException("{0} is full.".format(self.redo.fileName))
        self.p2CRedoRecordHeader.offset = sourceAddress - \
            self.storage.baseAddress
        self.p2CRedoRecordHeader.length = length
        # validate source range
        assert sourceAddress > self.storage.baseAddress
        assert self.p2CRedoRecordHeader.offset + \
            length < self.storage.realFileSize
#         cdef Offset newRedoOffset
        cdef void *redoRecordPayload = <void*>(self.p2CRedoRecordHeader+1)
        memcpy(redoRecordPayload, sourceAddress, length)
        MD5_Update(&self.md5Context, <void*>(self.p2CRedoRecordHeader),
                   sizeof(CRedoRecordHeader) + length)
        self.p2CRedoRecordHeader = <CRedoRecordHeader*>(redoRecordPayload +
                                                        length)

    cdef commit(self, lazy=False):
        MD5_Final((self.redo.p2Tail.checksum), &self.md5Context, )
        self.redo.p2Tail.length = (<void*>self.p2CRedoRecordHeader -
                                   <void*>self.redo.p2Tail)
        self.redo.p2Tail = <CTrxHeader*>self.p2CRedoRecordHeader
        self.redo.flush(lazy)
        self.redo = self.storage = None

cdef class Storage(MemoryMappedFile):

    cdef registerType(self, PersistentMeta ptype):
        if hasattr(self.schema, ptype.__name__):
            raise Exception(
                "Redefinition of type '{ptype.__name__}'.".format(ptype=ptype))
        setattr(self.schema, ptype.__name__, ptype)
        self.typeList.append(ptype)

    def _initialize(self):
        LOG.info("Initializing new file '{self.fileName}'".format(self=self))
        assert len(ptypesMagic) < lengthOfMagic
        cdef int i, j
        for i in range(numMetadata):
            self.p2FileHeader = self.p2FileHeaders[i] = \
                <CDbFileHeader*>self.baseAddress + i

            for j in range(len(ptypesMagic)):
                self.p2FileHeader.magic[j] = ptypesMagic[j]

            self.p2FileHeader.status = 'C'
            self.p2FileHeader.revision = i
            self.p2FileHeader.freeOffset = numMetadata*PAGESIZE

        self.p2FileHeader.status = 'D'
        self.p2LoHeader = self.p2FileHeaders[0]
        self.p2HiHeader = self.p2FileHeaders[1]

    def _mount(self):
        LOG.info("Mounting existing file '{self.fileName}'".format(self=self))
        self.p2HiHeader = self.p2LoHeader = NULL
        cdef int i
        for i in range(numMetadata):
            self.p2FileHeader = self.p2FileHeaders[i] = \
                <CDbFileHeader*>self.baseAddress + i
            if any(self.p2FileHeader.magic[j] != ptypesMagic[j]
                   for j in range(len(ptypesMagic))
                   ):
                raise Exception('File {self.fileName} is incompatible with '
                                'this version of the graph DB!'.format(
                                    self=self)
                                )
            if (self.p2LoHeader == NULL or
                self.p2LoHeader.revision > self.p2FileHeader.revision
                ):
                    self.p2LoHeader = self.p2FileHeader

            if (self.p2HiHeader == NULL or
                self.p2HiHeader.revision < self.p2FileHeader.revision
                ):
                    self.p2HiHeader = self.p2FileHeader

        if self.p2HiHeader.status != 'C':  # roll back
            LOG.info(
                "Latest shutdown was incomplete, restoring previous metadata.")
            self.p2FileHeader = self.p2HiHeader
            self.p2FileHeader[0] = self.p2LoHeader[0]
            if self.p2HiHeader.status != 'C':
                raise Exception("No clean metadata could be found!")
        else:
            LOG.debug("Latest shutdown was clean, using latest metadata.")
            self.p2FileHeader = self.p2LoHeader
            self.p2FileHeader[0] = self.p2HiHeader[0]
        self.p2FileHeader.status = 'D'
        self.p2FileHeader.revision += 1

    def __init__(self, fileName, unsigned long fileSize=0,
                 unsigned long stringRegistrySize=0
                 ):
        cdef unsigned long numPages = (
            0 if fileSize==0 else (fileSize-1)/PAGESIZE + 1 + numMetadata
        )
        MemoryMappedFile.__init__(self, fileName, numPages)
        LOG.debug("Highest metadata revision is {0}"
                  .format(self.p2HiHeader.revision))
        LOG.debug("Lowest metadata revision is {0}"
                  .format(self.p2LoHeader.revision))
        LOG.debug("Using metadata revision {0}"
                  .format(self.p2FileHeader.revision))
        if not self.isNew and fileSize > self.realFileSize:
            raise Exception("File {self.fileName} is of size "
                            "{self.realFileSize}, cannot resize it to "
                            "{fileSize}.".format(self=self, fileSize=fileSize)
                            )
        self.stringRegistrySize = stringRegistrySize
        self.schema = ModuleType('schema')
        self.typeList = list()

        self.define(Int)
        self.define(Float)
        self.define(__String('String'))
        cdef:
            PersistentMeta ListOfStrings = \
                self.define(List('__ListOfStrings')[self.schema.String])
            PersistentMeta SetOfStrings  = \
                self.define(Set('__SetOfStrings')[self.schema.String])

        if self.p2FileHeader.o2StringRegistry:
            LOG.debug("Using the existing stringRegistry")
            self.stringRegistry = SetOfStrings.createProxy(
                self.p2FileHeader.o2StringRegistry)
        else:
            LOG.debug("Creating a new stringRegistry")
            self.stringRegistry = SetOfStrings(self.stringRegistrySize)
            self.p2FileHeader.o2StringRegistry = self.stringRegistry.offset
        LOG.debug('self.p2FileHeader.o2StringRegistry: {0}'.format(
            hex(self.p2FileHeader.o2StringRegistry)))

        self.createTypes = (self.p2FileHeader.o2PickledTypeList == 0)
        if self.createTypes:
            LOG.debug("Creating a new schema")
            self.pickledTypeList = <PList>ListOfStrings()
            self.p2FileHeader.o2PickledTypeList = self.pickledTypeList.offset
            try:
                threadLocal.currentStorage = self
                StructureMeta('Structure', (PStructure,), dict())
                self.populateSchema()
            finally:
                threadLocal.currentStorage = None
        else:
            LOG.debug("Loading the previously saved schema")
            self.pickledTypeList = \
                <PList>(ListOfStrings.createProxy(self.p2FileHeader
                                                  .o2PickledTypeList)
                        )
            for s in self.pickledTypeList:
                t = loads(s.contents)
                if t[0] == '_typedef':
                    className, meta, proxyClass = t[1:4]
                    typeParams = [
                        getattr(self.schema, typeParam[1])
                        if (isinstance(typeParam, tuple) and
                            typeParam[0] == 'PersistentMeta')
                        else typeParam
                        for typeParam in t[4:]
                    ]
                    meta._typedef(self, className, proxyClass, *typeParams)
                elif t[0] == 'StructureMeta':
                    className, bases, attributeDict = t[1:4]
                    base2  = list()
                    for base in bases:
                        baseKind, baseX = base
                        if baseKind == 'persistentBase':
                            base = getattr(self.schema, baseX)
                        else:
                            assert baseKind == 'volatileBase', baseKind
                            base = baseX
                        base2.append(base)
                    for fieldName, fieldTypeName in t[4]:
                        attributeDict[fieldName] = getattr(
                            self.schema, fieldTypeName)
                    try:
                        threadLocal.currentStorage = self
                        StructureMeta(className, tuple(base2), attributeDict)
                    finally:
                        threadLocal.currentStorage = None
                else:
                    assert False
                del s  # do not leave a dangling proxy around

    def __flush(self):
        self.assertNotClosed()
        MemoryMappedFile.flush(self)
        self.p2FileHeader.status = 'C'
        MemoryMappedFile.flush(self)

    cpdef flush(self, bint async=False):
        LOG.debug("Flushing {}".format(self))
        self.__flush()
        cdef CDbFileHeader *p2FileHeader = self.p2FileHeader
        cdef unsigned long revision = p2FileHeader.revision + 1
        self.p2FileHeader = self.p2FileHeaders[revision % numMetadata]
        self.p2FileHeader[0] = p2FileHeader[0]
        self.p2FileHeader.revision = revision
        self.p2FileHeader.status = 'D'

    cpdef close(self):
        """ Flush and close the storage.

            Triggers a garbage collection to break any unreachable cycles
            referencing the storage.
        """
        LOG.debug("Closing {}".format(self))
        self.assertNotClosed()
        suspects = [o for o in gc.get_referrers(self)
                    if (isinstance(o, Persistent) and
                        o not in [self.__root, self.stringRegistry,
                                  self.pickledTypeList]
                        )
                    ]
        if suspects:
            LOG.warning('The following proxy objects are probably part of a '
                        'reference cycle: \n{}' .format(suspects)
                        )
        gc.collect()
        suspects = [o for o in gc.get_referrers(self)
                    if (isinstance(o, Persistent) and
                        o not in [self.__root, self.stringRegistry,
                                  self.pickledTypeList]
                        )
                    ]
        if suspects:
            raise ValueError("Cannot close {} - some proxies are still around:"
                             " {}".format(
                                 self, ' '.join([repr(s) for s in suspects]))
                             )
        self.__flush()
        MemoryMappedFile.close(self)

    cdef Offset allocate(self, int size) except 0:
        self.assertNotClosed()
        cdef:
            Offset origFreeOffset = self.p2FileHeader.freeOffset
            Offset newFreeOffset = self.p2FileHeader.freeOffset + size
        if newFreeOffset > self.realFileSize:
            raise DbFullException("{self.fileName} is full.".format(self=self))
        self.p2FileHeader.freeOffset = newFreeOffset
#         LOG.debug( "allocated: {origFreeOffset}, {size},
#               {newFreeOffset}".format(**locals()))
        return origFreeOffset

    property root:
        def __get__(self):
            cdef PersistentMeta Root
            self.assertNotClosed()
            if self.__root is None:
                LOG.debug(
                    'self.createTypes: {self.createTypes}'.format(self=self))
                if self.createTypes:
                    for ptype in self.typeList:
                        if ptype.__name__ not in ('String', 'Int', 'Float', ):
                            x = ptype.reduce()
#                             LOG.debug( 'pickle data:'+ repr(x))
                            s = self.stringRegistry.get(dumps(x))
                            self.pickledTypeList.append(s)
                            del s  # do not leave a dangling proxy around
                    LOG.debug("Saved the new schema.")
                try:
                    Root = self.schema.Root
                except AttributeError:
                    raise Exception(
                        "The schema contains no type called 'Root'.")
                LOG.debug('self.p2FileHeader.o2Root #1: {0}'.format(
                    hex(self.p2FileHeader.o2Root)))
                if self.p2FileHeader.o2Root:
                    self.__root = Root.createProxy(self.p2FileHeader.o2Root)
                else:
                    self.__root = Root()
                    self.p2FileHeader.o2Root = self.__root.offset
                LOG.debug('self.p2FileHeader.o2Root #2: {0}'.format(
                    hex(self.p2FileHeader.o2Root)))
            return self.__root

    def defineType(Storage storage, TypeDescriptor typeDescriptor):
        cdef:
            type meta = typeDescriptor.meta
        # need to check if they are filled in
        typeDescriptor.verifyTypeParameters(typeDescriptor.typeParameters)
        return meta._typedef(storage, typeDescriptor.className,
                            typeDescriptor.proxyClass,
                            *typeDescriptor.typeParameters)

    def define(Storage storage, object o):
        if isinstance(o, TypeDescriptor):
            return storage.defineType(o)
        elif isinstance(o, type) and issubclass(o, TypeDescriptor):
            return storage.defineType(o())
        elif isinstance(o, ModuleType):
            return o.defineTypes(storage)
        else:
            raise TypeError("Don't know how to define {o}".format(o=repr(o)))

    cpdef object internValue(Storage self, str typ, value):
        if typ == 'time':
            return mktime(strptime(value, '%Y-%m-%d %H:%M:%S %Z'))
        elif typ == 'string':
            return self.stringRegistry.find(value)
        elif typ is None:
            return value
        else:
            raise TypeError(str(typ))

    def populateSchema(self):
        pass
