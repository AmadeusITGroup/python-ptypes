from libc.stdlib cimport abort

ctypedef unsigned long Offset

cdef class Persistent(object):
    """ Base class for all the proxy classes for persistent objects.
    """
    cdef:
        readonly Offset offset
        readonly PersistentMeta ptype
        Storage  storage
        void *p2InternalStructure

    cdef int richcmp(Persistent self, other, int op) except? -123
    cdef revive(Persistent p)
    cdef store(Persistent self, void *target)

# p2InternalStructure points at a persistent object embedded inside
# another persistent object
cdef class AssignedByValue(Persistent):
    pass

# p2InternalStructure points at a stand-alone object on the heap
cdef class AssignedByReference(Persistent):
    pass

cdef inline Offset allocateStorage(PersistentMeta ptype) except 0:
    return ptype.storage.allocate(ptype.allocationSize)

cdef class PersistentMeta(type):
    """ Abstract base meta class for all persistent types.
    """
    cdef:
        readonly Storage storage
        int             allocationSize  # used for allocating memory

        # used in assignments, must equal to allocationSize when the assignment
        # semantics of the type is store-by-value
        int             assignmentSize
        Offset(*resolve)(PersistentMeta ptype, Offset offset) except -1

        type            proxyClass
        readonly str    __name__

    cdef inline void*  offset2Address(PersistentMeta ptype,
                                      Offset         offset
                                      ) except NULL:
        ptype.storage.assertNotClosed()
        return ptype.storage.baseAddress + offset

    cdef inline Offset address2Offset(PersistentMeta ptype, void* address):
        return address - ptype.storage.baseAddress

    cdef inline Persistent createProxyFA(PersistentMeta ptype, void* address):
        return ptype.createProxy(ptype.address2Offset(address))

    cdef Persistent createProxy(PersistentMeta ptype, Offset offset)

    # The resolveAndCreateProxy* methods require a pointer or an offset to
    # an "embedded" area (e.g. fields). *Never* invoke these methods on
    # pointers/offsets at areas containing a by-ref object!
    # They create a proxy out of ptype.
    cdef inline Persistent resolveAndCreateProxy(PersistentMeta ptype,
                                                 Offset offset
                                                 ):
        return ptype.createProxy(ptype.resolve(ptype, offset))

    cdef inline Persistent resolveAndCreateProxyFA(PersistentMeta   ptype,
                                                   void*            address
                                                   ):
        return ptype.createProxy(ptype.resolve(ptype,
                                               address - ptype.storage.baseAddress
                                               )
                                 )

    cdef void clear(PersistentMeta ptype, Offset o2Target)
    cdef assign(PersistentMeta ptype, void *target, source, )
    cdef int isAssignedByValue(PersistentMeta ptype) except? -123
    cdef assertType(PersistentMeta ptype, Persistent persistent)

cdef class TypeDescriptor(object):
    # In derived classes the below class-attributes must be added:
    #   meta: a subclass of PersistentMeta to be used with the type
    #   proxyClass: a subclass of Persistent
    #   minNumberOfParameters: min
    #   maxNumberOfParameters: and max number of parameters of the type

    cdef:
        readonly str className
        readonly tuple typeParameters

cdef class Int(TypeDescriptor):
    pass
cdef class Float(TypeDescriptor):
    pass
cdef class __String(TypeDescriptor):
    pass
cdef class Set(TypeDescriptor):
    pass
cdef class Dict(TypeDescriptor):
    pass
cdef class DefaultDict(Dict):
    pass
cdef class List(TypeDescriptor):
    pass

cdef:
    struct CHashTable:
        unsigned long _capacity, _used
        Offset        _mask, o2EntryTable

    struct CHashEntry:
        bint isUsed

cdef class HashEntryMeta(PersistentMeta):
    cdef:
        PersistentMeta keyClass
        PersistentMeta valueClass
        Offset o2Key, o2Value           # offsets from the head of the entry!

cdef class PHashEntry(AssignedByValue):
    pass

cdef class HashTableMeta(PersistentMeta):
    cdef:
        HashEntryMeta hashEntryClass

cdef class PHashTable(AssignedByReference):
    cdef:
        HashEntryMeta hashEntryClass
        PersistentMeta keyClass
        PersistentMeta valueClass
        Offset o2Key, o2Value           # offsets from the head of the entry!

        incrementUsed(self)
        CHashEntry* _findEntry(self, object key) except NULL
        missing(self, CHashEntry* entry, key)

    cpdef Persistent get(self, object key, value=?)

    cdef inline CHashTable *getP2IS(self):
        return <CHashTable *>self.p2InternalStructure

    cdef inline Offset getO2Entry(self, unsigned long i):
        return (self.getP2IS().o2EntryTable +
                i*self.hashEntryClass.assignmentSize)

    cdef inline CHashEntry* getP2Entry(self, unsigned long i):
        return <CHashEntry*><unsigned long>(self.ptype.storage.baseAddress +
                                            self.getO2Entry(i)
                                            )

    cdef inline Offset getO2Key(self, Offset      o2Entry):
        return o2Entry + self.o2Key

    cdef inline Offset getO2Value(self, Offset      o2Entry):
        return o2Entry + self.o2Value

    cdef inline void*  getP2Key(self, CHashEntry* p2Entry):
        return (<void*>p2Entry) + self.o2Key

    cdef inline void*  getP2Value(self, CHashEntry* p2Entry):
        return (<void*>p2Entry) + self.o2Value

    cdef inline Persistent getKey(self, CHashEntry* p2Entry):
        return self.keyClass  .resolveAndCreateProxyFA(self.getP2Key(p2Entry))

    cdef inline setKey(self, CHashEntry* p2Entry, key):
        if not p2Entry.isUsed:
            self.incrementUsed()
        p2Entry.isUsed = 1
        self.keyClass.assign(self.getP2Key(p2Entry), key)

    cdef inline Persistent getValue(self, CHashEntry* p2Entry):
        return self.valueClass.\
            resolveAndCreateProxyFA(self.getP2Value(p2Entry))

    cdef inline setValue(self, CHashEntry* p2Entry, value):
        self.valueClass.assign(self.getP2Value(p2Entry), value)

cdef class PDefaultHashTable(PHashTable):
    pass

cdef class PString(AssignedByReference):
    cdef inline char *getCharPtr(self):
        return <char*>self.p2InternalStructure+sizeof(int)

    cdef inline int   getSize(self):
        return (<int*>self.p2InternalStructure)[0]

    cdef inline bytes getString(self):
        return self.getCharPtr()[:self.getSize()]

cdef struct CList:
    Offset o2FirstEntry, o2LastEntry

cdef struct CListEntry:
    Offset o2NextEntry  # o2Value is handled dynamically

cdef class ListMeta(PersistentMeta):
    cdef:
        PersistentMeta valueClass
        Offset o2Value

cdef class PList(AssignedByReference):

    cdef inline CList *getP2IS(self):
        return <CList *>self.p2InternalStructure

    cdef CListEntry *newEntry(self, value, Offset* o2NewEntry)
    cpdef insert(PList self, object value)
    cpdef append(PList self, object value)

cdef class StructureMeta(PersistentMeta):
    cdef:
        readonly   list    fields    # list of (name, ptype.__name__) tuples
        readonly   type    NamedTupleClass
        dict    pfields   # list of PField objects

    cdef addField(StructureMeta ptype, name, PersistentMeta fieldType)

cdef class PStructure(AssignedByReference):
    cdef get(PStructure self)
    cdef set(PStructure self, value)

cdef class PField(object):
    cdef:
        readonly int offset
        readonly PersistentMeta ptype
        readonly str name

        object      set(PField self, PStructure owner, value)
        Persistent  get(PField self, PStructure owner)

cdef class MemoryMappedFile(object):
    cdef:
        void            *baseAddress
        void            *endAddress
        long            fd
        int             isNew
        readonly str    fileName
        readonly unsigned long long    numPages, realFileSize

    cpdef flush(self, bint async=?)
    cpdef close(self)

    cdef inline assertNotClosed(self):
        if self.baseAddress == NULL:
            raise ValueError(
                'Storage {self.fileName} is closed.'.format(self=self))


DEF lengthOfMagic = 15
DEF numMetadata = 2
DEF PAGESIZE = 4096

cdef struct CDbFileHeader:
    char magic[lengthOfMagic]
    char status
    unsigned long revision
    unsigned long lastAppliedRedoFileNumber
    Offset o2lastAppliedTrx
    Offset freeOffset, o2StringRegistry, o2PickledTypeList, o2Root

cdef class Storage(MemoryMappedFile):
    cdef:
        CDbFileHeader       *p2FileHeaders[numMetadata]
        CDbFileHeader       *p2HiHeader
        CDbFileHeader       *p2LoHeader
        CDbFileHeader       *p2FileHeader

        long                    stringRegistrySize
        readonly bint           createTypes
        readonly                schema  # ModuleType
        list                    typeList

        # Persistent objects
        PList                   pickledTypeList
        Persistent              __root
        readonly PHashTable     stringRegistry

        object                  registerType(self, PersistentMeta ptype)
        Offset                  allocate(self, int size) except 0

    cpdef object          internValue(Storage self, str typ, value)
