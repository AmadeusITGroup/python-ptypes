# cython: profile=False

from libc.stdlib cimport malloc, free, rand, RAND_MAX

from .storage cimport PersistentMeta, Persistent, AssignedByReference
from .storage cimport Offset, Storage, TypeDescriptor, allocateStorage
from .query   cimport BindingRule, QueryContext

import logging
LOG = logging.getLogger(__name__)

############################  SkipList #############################

cdef struct CSkipNode:
    Offset o2Next  # array of pointers to CSkipNode objects
    unsigned int  numberOfLevels

cdef inline CSkipNode* getNextAtLevel(Storage storage, CSkipNode *p2CSkipNode,
                                      int level) except NULL:
    cdef CSkipNode *x = (
        <CSkipNode* >(storage.baseAddress +
                      (<unsigned long*>(storage.baseAddress +
                                        p2CSkipNode.o2Next)
                       )[level]
                      )
    )
    # print 'getNextAtLevel', hex(<unsigned long><void*>x)
    return x
cdef inline setNextAtLevel(Storage storage, CSkipNode *p2CSkipNode, int level,
                           CSkipNode* p2):
    (<unsigned long *>(storage.baseAddress+p2CSkipNode.o2Next))[level] = \
        <void*>p2 - storage.baseAddress


cdef class SkipNodeMeta(PersistentMeta):
    cdef:
        PersistentMeta valueClass
        Offset  o2Value           # offsets from the head of the entry!
        str     sortOrder
        object  compare, getKeyFromValue

    def __init__(ptype, Storage       storage,
                 str              className,
                 type             proxyClass,
                 PersistentMeta   valueClass,
                 object           sortOrder,
                 ):
        assert issubclass(proxyClass, PSkipNode), proxyClass
        ptype.o2Value = sizeof(CSkipNode)
        PersistentMeta.__init__(ptype, storage, className, proxyClass,
                                ptype.o2Value + valueClass.assignmentSize)
        ptype.valueClass  =  valueClass
        ptype.sortOrder = sortOrder
        if sortOrder is None:
            ptype.compare = ptype.getKeyFromValue = None
        else:
            localNameSpace = dict()
            globalNameSpace = dict()
            exec (sortOrder, globalNameSpace, localNameSpace)
            ptype.getKeyFromValue = localNameSpace.get('getKeyFromValue')
            ptype.compare = localNameSpace.get('compare')

    def reduce(ptype):
        assert False, ("The name of SkipNodeMeta instances must start "
                       "with '__' to prevent pickling them!")


cdef class PSkipNode(AssignedByReference):

    cdef inline CSkipNode *getP2IS(PSkipNode self):
        return <CSkipNode *>self.p2InternalStructure

    cdef inline void* getP2Value(PSkipNode self):
        return self.p2InternalStructure + (<SkipNodeMeta>self.ptype).o2Value

    cdef inline Persistent getValue(self):
        return (<SkipNodeMeta>self.ptype).valueClass.\
            resolveAndCreateProxyFA(self.getP2Value())

    cdef inline setValue(self, value):
        (<SkipNodeMeta>self.ptype).valueClass.assign(self.getP2Value(), value)

    cdef inline Persistent getKey(self):
        getKeyFromValue = (<SkipNodeMeta>self.ptype).getKeyFromValue
        return (getKeyFromValue(self.getValue()) if getKeyFromValue
                else self.getValue())

    def __init__(PSkipNode self, object value, level=0):
        self.setValue(value)
        self.getP2IS().numberOfLevels = level

        # Array of offsets to CSkipNodes
        self.getP2IS().o2Next = \
            self.ptype.storage.allocate(level*sizeof(Offset))

        # Theoretically we would need to initialize the allocated array here.
        # In practice it will be initialized when it is inserted into the list.

    def __str__(self):
        return "<{0} @offset {1} key {2}>"\
            .format(self.ptype.__name__, hex(self.offset), self.getKey())

    def __repr__(self):
        return "<{0} @offset={1} key={2} value={3} o2Next={4} #lvls={5}>"\
            .format(self.ptype.__name__, hex(self.offset), self.getKey(),
                    self.getValue(), hex(self.getP2IS().o2Next),
                    self.getP2IS().numberOfLevels)

    cdef int richcmp(PSkipNode self, other, int op) except? -123:
        cdef:
            Persistent key = self.getKey()
            int doesDiffer
        if (<SkipNodeMeta>self.ptype).compare:
            doesDiffer = (<SkipNodeMeta>self.ptype).compare(key, other)
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
        else:
            return key.richcmp(other, op)


cdef CSkipNode2str(CSkipNode *node, Storage storage):
    return "[@offset={0} key={1} o2Value={2} o2Next={3} #lvls={4}]"\
        .format(hex(<void*>node-storage.baseAddress),
                'node.key', 'hex(node.o2Value)', hex(node.o2Next),
                node.numberOfLevels)  # XXX print key properly

cdef:
    struct CSkipList:
        Offset o2Head
        unsigned long actualSize

    # number of levels will be cc. log(number-of-elements)/log(3)
    long limit4randomNumber = RAND_MAX / 3

cdef class SkipListMeta(PersistentMeta):
    cdef:
        SkipNodeMeta entryClass

    @classmethod
    def _typedef(PersistentMeta   meta,
                Storage          storage,
                str              className,
                type             proxyClass,
                PersistentMeta   valueClass,
                str              sortOrder=None,
                ):
        if valueClass is None:
            raise ValueError("The type parameter specifying the type of values"
                             " cannot be {0}".format(valueClass)
                             )
        cdef:
            str entryName = ('__{valueClass.__name__}AsSkipListNode'
                             .format(valueClass=valueClass)
                             )
            SkipNodeMeta entryClass = SkipNodeMeta._typedef(storage, entryName,
                                                           PSkipNode,
                                                           valueClass,
                                                           sortOrder)

        return super(SkipListMeta, meta)._typedef(storage, className,
                                                 proxyClass, entryClass)

    def __init__(ptype,
                 Storage      storage,
                 str          className,
                 type         proxyClass,
                 SkipNodeMeta entryClass,
                 ):
        assert issubclass(proxyClass, PSkipList), proxyClass
        PersistentMeta.__init__(ptype, storage, className, proxyClass,
                                sizeof(CSkipList))
        ptype.entryClass  =  entryClass

    def reduce(ptype):
        return ('_typedef', ptype.__name__, ptype.__class__, ptype.proxyClass,
                ('PersistentMeta', ptype.entryClass.valueClass.__name__),
                ptype.entryClass.sortOrder,
                )


cdef class PSkipList(AssignedByReference):

    cdef inline CSkipList *getP2IS(self):
        return <CSkipList *>self.p2InternalStructure

    def __init__(PSkipList self, ):
        # The head node is never visible outside, so its key and value do not
        # matter. Its only important parts are o2Next (its array of offsets of
        # the next nodes) and numberOfLevels (the size of the array).
        # The skip list cannot have a node with an array bigger than this one.
        self.getP2IS().o2Head = allocateStorage(self.ptype)
        cdef CSkipNode *head = self.getHead()
        head.numberOfLevels = 0
        self.getP2IS().actualSize=0

    def __repr__(self):
        return ("<persistent {0} object @offset {1}>"
                .format(self.ptype.__name__, hex(self.offset))
                )

    def _printNodes(PSkipList self):
        cdef:
            CSkipNode *node
            CSkipNode *head = self.getHead()
        for level in range(head.numberOfLevels-1, -1, -1):
            print 'level %d:' % level,
            node = self.getHead()
            while node != self.ptype.storage.baseAddress:
                print "{0} =>".format(CSkipNode2str(node, self.ptype.storage)),
                node = getNextAtLevel(self.ptype.storage, node, level)
            print 'END'

    cdef inline CSkipNode *getHead(PSkipList self):
        return <CSkipNode *>(self.ptype.storage.baseAddress +
                             self.getP2IS().o2Head)

    def __iter__(PSkipList self):
        return self.range(None, None)

    def range(PSkipList self, object fro=None, object to=None):
        # This is a generator, cdef is not possible!
        cdef:
            CSkipNode **cutList
            CSkipNode *head = self.getHead()
            CSkipNode *cSkipNode
            PersistentMeta entryClass = (<SkipListMeta>self.ptype).entryClass
            PSkipNode skipNode
        if head.numberOfLevels > 0:
            if fro is None:
                cSkipNode = getNextAtLevel(self.ptype.storage, head, 0)
            else:
                cutList= self.getCutList(fro)
                cSkipNode = getNextAtLevel(self.ptype.storage, cutList[0], 0)
                free(cutList)
            while True:
                if <void*>cSkipNode == self.ptype.storage.baseAddress:
                    break
                skipNode = entryClass.createProxyFA(cSkipNode)
                if to is not None and skipNode >= to:
                    break
                yield skipNode.getValue()
                cSkipNode = getNextAtLevel(self.ptype.storage, cSkipNode, 0)

    cdef CSkipNode ** getCutList(PSkipList self, object value) except NULL:
        """ Find (at each level) the pointer to the Node after the insert.
        """
        cdef:
            #  nodeAtLevel will be initialized with the head node
            CSkipNode *nodeAtLevel = self.getHead()
            int level = nodeAtLevel.numberOfLevels -1
            CSkipNode* nextNodeAtLevel
            PersistentMeta entryClass = (<SkipListMeta>self.ptype).entryClass
            PSkipNode skipNode
            CSkipNode **cutList
        cutList = <CSkipNode **>malloc(nodeAtLevel.numberOfLevels *
                                       sizeof(CSkipNode *)
                                       )
        try:
            while level >= 0:
                while True:
                    nextNodeAtLevel = getNextAtLevel(self.ptype.storage,
                                                     nodeAtLevel, level)
                    if nextNodeAtLevel == self.ptype.storage.baseAddress:
                        break
                    skipNode = entryClass.createProxyFA(nextNodeAtLevel)
                    if skipNode >= value:
                        break
                    nodeAtLevel = nextNodeAtLevel
                cutList[level] = nodeAtLevel
                level -= 1
            return cutList
        except:
            if cutList:
                free(cutList)
            raise

    cdef CSkipNode * find(self, object key) except NULL:
        cdef:
            CSkipNode **cutList
            CSkipNode *cSkipNode
            CSkipNode *head = self.getHead()
            PersistentMeta entryClass = (<SkipListMeta>self.ptype).entryClass
            PSkipNode skipNode

        if head.numberOfLevels > 0:
            cutList= self.getCutList(key)
            cSkipNode = getNextAtLevel(self.ptype.storage, cutList[0], 0)
            free(cutList)
            if cSkipNode != self.ptype.storage.baseAddress:
                skipNode = entryClass.createProxyFA(cSkipNode)
                if skipNode == key:
                    return cSkipNode
        raise KeyError(key)

    def __getitem__(self, object key):
        cdef:
            CSkipNode *cSkipNode = self.find(key)
            PersistentMeta entryClass = (<SkipListMeta>self.ptype).entryClass
        return (<PSkipNode>entryClass.createProxyFA(cSkipNode)).getValue()

    def insert(self, object value):
        cdef:
            SkipNodeMeta entryClass = (<SkipListMeta>self.ptype).entryClass
            CSkipNode *head = self.getHead()
            Offset *next
            Offset *newNext
            int i

        level = self.randomLevel()
        if head.numberOfLevels < level:
            next = <Offset *>(self.ptype.storage.baseAddress + head.o2Next)
            head.o2Next = self.ptype.storage.allocate(sizeof(Offset)*level)
            newNext = <Offset *>(self.ptype.storage.baseAddress + head.o2Next)
            for i in range(head.numberOfLevels):
                newNext[i] = next[i]
            for i in range(head.numberOfLevels, level):
                newNext[i] = 0
            head.numberOfLevels = level

        cdef:
            PSkipNode node = entryClass(value, level)
            CSkipNode **cutList = self.getCutList(node.getKey())
        for i in range(level):
            setNextAtLevel(self.ptype.storage, node.getP2IS(), i,
                           getNextAtLevel(self.ptype.storage, cutList[i], i))
            setNextAtLevel(self.ptype.storage, cutList[i], i, node.getP2IS())
        free(cutList)
        self.getP2IS().actualSize+=1

    cdef randomLevel(self):
        cdef int level = 1
        while rand() < limit4randomNumber:
            level += 1
        return level

cdef class SkipList(TypeDescriptor):
    meta = SkipListMeta
    proxyClass = PSkipList
    minNumberOfParameters=1
    maxNumberOfParameters=2


def defineTypes(Storage p):
    pass

########## Query BindingRules for persistent collections ###################

cdef class Range(BindingRule):

    """ Bind the next value in a skip-list to the name of the variable.
    """
    cdef:
        str indexName
        BindingRule fromBindingRule, toBindingRule

    def __init__(self, str indexName, BindingRule fro, BindingRule to,
                 bint shortCut=False
                 ):
        BindingRule.__init__(self, fro, to, shortCut=shortCut)
        self.indexName = indexName
        self.fromBindingRule = fro
        self.toBindingRule = to

    cdef getAll(Range self, query, QueryContext result):
        skipList = getattr(query.storage.root, self.indexName)
        for value in skipList.range(result.dick[self.fromBindingRule.name],
                                    result.dick[self.toBindingRule.name]):
            result.setattr(self.name, value)
            self.getAllRecursively(query, result)
