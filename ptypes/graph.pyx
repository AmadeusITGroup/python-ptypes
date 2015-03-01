# cython: profile=False

from .storage cimport PersistentMeta, Persistent, AssignedByReference
from .storage cimport Offset, Storage, TypeDescriptor
from .query   cimport BindingRule, QueryContext

import logging
LOG = logging.getLogger(__name__)

from .storage import DefaultDict

########################### Nodes of a graph ###############################
cdef:
    struct CNode:
        Offset   o2FirstInEdgeKind, o2FirstOutEdgeKind

    enum EdgeDirection:
        In  = 1
        Out = 2

cdef class NodeMeta(PersistentMeta):
    cdef:
        PersistentMeta  valueClass
        Offset          o2Value

    def __init__(ptype,
                 Storage       storage,
                 str              className,
                 type             proxyClass,
                 PersistentMeta   valueClass,
                 ):
        assert issubclass(proxyClass, PNode), proxyClass
        ptype.o2Value = sizeof(CNode)
        PersistentMeta.__init__(ptype, storage, className, proxyClass,
                                ptype.o2Value + valueClass.assignmentSize)
        ptype.valueClass  =  valueClass

    def reduce(ptype):
        return ('_typedef', ptype.__name__, ptype.__class__, ptype.proxyClass,
                ('PersistentMeta', ptype.valueClass.__name__)
                )

cdef class PNode(AssignedByReference):

    cdef inline CNode *getP2IS(PNode self):
        return <CNode *>self.p2InternalStructure
    cdef inline void  *getP2Value(PNode self):
        return self.p2InternalStructure + (<NodeMeta>self.ptype).o2Value

    cdef inline Persistent getValue(self):
        return (<NodeMeta>self.ptype).valueClass\
            .resolveAndCreateProxyFA(self.getP2Value())
    cdef inline setValue(self, value):
        (<NodeMeta>self.ptype).valueClass.assign(self.getP2Value(), value)

    def __init__(PNode self, object value=None):
        self.getP2IS().o2FirstInEdgeKind = 0
        self.getP2IS().o2FirstOutEdgeKind = 0
        self.setValue(value)

    def __repr__(self):
        return ("<persistent graph node '{0}' @offset {1} referring to {2} >"
                .format(self.ptype.__name__, hex(self.offset), self.getValue())
                )

    property contents:
        def __get__(self):
            return self.getValue()

        def __set__(self, value):
            self.setValue(value)

    cdef CEdgeKind *getP2EdgeKind(PNode         self,
                                  EdgeMeta      edgeClass,
                                  EdgeDirection edgeDirection,
                                  int           createNew=0) except NULL:
        # print "getP2EdgeKind", self, hex(o2Name), edgeDirection, createNew

        cdef Offset *p2o2FirstEdgeKind
        if edgeDirection == In:
            p2o2FirstEdgeKind = &self.getP2IS().o2FirstInEdgeKind
        elif edgeDirection == Out:
            p2o2FirstEdgeKind = &self.getP2IS().o2FirstOutEdgeKind
        else:
            raise ValueError("In or Out must be set in the 'edgeDirection' "
                             "parameter!")

        cdef:
            Offset o2EdgeKind = p2o2FirstEdgeKind[0]
            CEdgeKind *p2CEdgeKind = NULL
            CEdgeKind *p2MatchingCEdgeKind = NULL

        while o2EdgeKind:
            p2CEdgeKind = <CEdgeKind*>(self.ptype.storage.baseAddress +
                                       o2EdgeKind)
            if p2CEdgeKind.o2ClassName == edgeClass.o2Name:
                p2MatchingCEdgeKind = p2CEdgeKind
                break
            o2EdgeKind = p2CEdgeKind.o2NextEdgeKind

        if o2EdgeKind == 0:
            if createNew:
                # create a new EdgeKind
                o2EdgeKind = self.ptype.storage.allocate(sizeof(CEdgeKind))
                p2MatchingCEdgeKind = \
                    <CEdgeKind*>(self.ptype.storage.baseAddress + o2EdgeKind)
                p2MatchingCEdgeKind.o2NextEdgeKind = p2o2FirstEdgeKind[0]
                p2MatchingCEdgeKind.o2ClassName = edgeClass.o2Name
                p2o2FirstEdgeKind[0] = o2EdgeKind
            else:
                raise ValueError("No edge of type '{0}'."
                                 .format(edgeClass.__name__))
        return p2MatchingCEdgeKind

    def inEdges(PNode self, EdgeMeta edgeClass):
        return self.edges(edgeClass, In)

    def outEdges(PNode self, EdgeMeta edgeClass):
        return self.edges(edgeClass, Out)

    # generators cannot be cpdef !
    def edges(PNode self, EdgeMeta edgeClass, EdgeDirection edgeDirection):
        assert edgeClass.storage is self.ptype.storage, (edgeClass.storage,
                                                         self.ptype.storage)
        cdef:
            CEdgeKind       *p2CEdgeKind
            Offset   o2Edge      = 0
            CEdge           *p2edge
        try:
            p2CEdgeKind = self.getP2EdgeKind(edgeClass, edgeDirection)
        except ValueError:
            pass
        else:
            o2Edge = p2CEdgeKind.o2FirstEdge
        while o2Edge:
            #             print '  o2Edge', hex(o2Edge)
            yield edgeClass.createProxy(o2Edge)
            p2edge = <CEdge*>(self.ptype.storage.baseAddress + o2Edge)
            if edgeDirection == In:  # optimize!
                o2Edge = p2edge.o2NextEdgeOfToNode
            elif edgeDirection == Out:
                o2Edge = p2edge.o2NextEdgeOfFromNode
            else:
                raise ValueError("In or Out must be set in the 'edgeDirection'"
                                 " parameter!")

cdef class Node(TypeDescriptor):
    meta = NodeMeta
    proxyClass = PNode
    minNumberOfParameters=1
    maxNumberOfParameters=1

############################# Edges of a graph ##############################

cdef struct CEdgeKind:
    Offset   o2ClassName, o2FirstEdge, o2NextEdgeKind

cdef struct CEdge:
    Offset   o2FromNode, o2ToNode, o2NextEdgeOfFromNode, o2NextEdgeOfToNode

cdef class EdgeMeta(PersistentMeta):
    cdef:
        PersistentMeta  valueClass
        NodeMeta        fromNodeClass, toNodeClass

        # cache it; avoid calling stringRegistry.get(ptype.__name__)
        Offset   o2Name
        Offset          o2Value

    def __init__(EdgeMeta  ptype,
                 Storage       storage,
                 str              className,
                 type             proxyClass,
                 PersistentMeta   fromNodeClass,
                 PersistentMeta   toNodeClass,
                 PersistentMeta   valueClass,
                 ):
        assert issubclass(proxyClass, PEdge), proxyClass
        ptype.o2Value = sizeof(CEdge)
        PersistentMeta.__init__(ptype, storage, className, proxyClass,
                                ptype.o2Value + valueClass.assignmentSize)
        ptype.valueClass     =  valueClass
        assert ptype.valueClass.storage == storage
        ptype.fromNodeClass  =  fromNodeClass
        assert ptype.fromNodeClass.storage == storage
        ptype.toNodeClass  =  toNodeClass
        assert ptype.toNodeClass.storage == storage
        ptype.o2Name = storage.stringRegistry.get(ptype.__name__).offset

    def reduce(ptype):
        return ('_typedef', ptype.__name__, ptype.__class__, ptype.proxyClass,
                ('PersistentMeta', ptype.fromNodeClass.__name__),
                ('PersistentMeta', ptype.toNodeClass.__name__),
                ('PersistentMeta', ptype.valueClass.__name__),
                )

cdef class PEdge(AssignedByReference):

    cdef inline CEdge *getP2IS(PEdge self):
        return <CEdge *>self.p2InternalStructure

    cdef inline void  *getP2Value(PEdge self):
        return self.p2InternalStructure + (<EdgeMeta>self.ptype).o2Value

    cdef inline Persistent getValue(self):
        return (<EdgeMeta>self.ptype).valueClass\
            .resolveAndCreateProxyFA(self.getP2Value())
    cdef inline setValue(self, value):
        (<EdgeMeta>self.ptype).valueClass.assign(self.getP2Value(), value)

    def __init__(PEdge self, PNode fromPNode not None, PNode toPNode not None,
                 Persistent value=None):
        cdef EdgeMeta edgeClass = <EdgeMeta>self.ptype
#         print '_init_', self.offset, edgeClass.o2Name
        assert fromPNode.ptype.storage is edgeClass.storage, \
            (fromPNode.ptype.storage, edgeClass.storage)
        assert toPNode.ptype.storage is edgeClass.storage, \
            (toPNode.ptype.storage, edgeClass.storage)
        if fromPNode.ptype != edgeClass.fromNodeClass:
            raise ValueError("{0} expects an instance of {expected} as "
                             "fromNode, not a {fromPNode.ptype} instance"
                             .format(edgeClass.__name__,
                                     expected=edgeClass.fromNodeClass,
                                     fromPNode=fromPNode)
                             )
        if toPNode  .ptype != edgeClass.toNodeClass:
            raise ValueError("{0} expects an instance of {expected} as "
                             "toNode, not a {toPNode.ptype} instance"
                             .format(edgeClass.__name__,
                                     expected=edgeClass.toNodeClass,
                                     toPNode=toPNode)
                             )
        self.getP2IS().o2FromNode = fromPNode.offset
        self.getP2IS().o2ToNode   = toPNode  .offset

        cdef:
            # find the edge types of our class
            CEdgeKind *p2CEdgeKindOfFromNode = \
                fromPNode.getP2EdgeKind(edgeClass, Out, 1)

            CEdgeKind *p2CEdgeKindOfToNode   = \
                toPNode  .getP2EdgeKind(edgeClass, In, 1)

        # add the edge to the edge types
        self.getP2IS().o2NextEdgeOfFromNode = p2CEdgeKindOfFromNode.o2FirstEdge
        self.getP2IS().o2NextEdgeOfToNode   = p2CEdgeKindOfToNode  .o2FirstEdge
        p2CEdgeKindOfFromNode.o2FirstEdge = self.offset
        p2CEdgeKindOfToNode  .o2FirstEdge = self.offset

        self.setValue(value)

    cdef PNode getFromNode(PEdge self):
        cdef EdgeMeta edgeClass = <EdgeMeta>self.ptype
        return edgeClass.fromNodeClass.createProxy(self.getP2IS().o2FromNode)

    cdef PNode getToNode(PEdge self):
        cdef EdgeMeta edgeClass = <EdgeMeta>self.ptype
        return edgeClass.toNodeClass.createProxy(self.getP2IS().o2ToNode)

    property fromNode:
        def __get__(PEdge self):
            return self.getFromNode()

    property toNode:
        def __get__(PEdge self):
            return self.getToNode()

    property contents:
        def __get__(self):
            return self.getValue()

        def __set__(self, value):
            self.setValue(value)

    def __repr__(self):
        return ("<persistent graph edge '{0}' @offset {1} referring to {2} >"
                .format(self.ptype.__name__, hex(self.offset), self.getValue())
                )


cdef class Edge(TypeDescriptor):
    meta = EdgeMeta
    proxyClass = PEdge
    minNumberOfParameters=3
    maxNumberOfParameters=3

######################### BindingRules for graphs ###########################

cdef class NodeContents(BindingRule):
    """ Bind the contents of a node to the name of the variable.
    """
    cdef:
        BindingRule nodeBindingRule

    def __init__(self, BindingRule nodeBindingRule, bint shortCut=False):
        BindingRule.__init__(self, nodeBindingRule, shortCut=shortCut)
        self.nodeBindingRule = nodeBindingRule

    cdef getAll(self, query, QueryContext result):
        cdef PNode node = result.getattr(self.nodeBindingRule.name)
        try:
            result.setattr(self.name, node.getValue())
        except Exception as e:
            e.args = e.args[0] + (" while accessing the contents of {0} in "
                                  "bindingRule '{1}'".format(node, self.name)
                                  ),
            raise
        self.getAllRecursively(query, result)

cdef class NodeAttribute(BindingRule):
    """ Bind the value of an attribute of a node to the name of the variable.
    """
    cdef:
        readonly str attributeName
        BindingRule nodeBindingRule

    def __init__(self, BindingRule nodeBindingRule, str attributeName=None,
                 bint shortCut=False
                 ):
        BindingRule.__init__(self, nodeBindingRule, shortCut=shortCut)
        self.nodeBindingRule = nodeBindingRule
        self.attributeName = attributeName

    cdef getAll(self, query, QueryContext result):
        cdef PNode node = result.getattr(self.nodeBindingRule.name)
        try:
            attributeValue = getattr(node.getValue(),
                                     self.attributeName or self.name)
            result.setattr(self.name, attributeValue)
        except Exception as e:
            e.args = e.args[0] + (" while accessing attribute '{0}' of the "
                                  "contents of {1} in bindingRule '{2}'"
                                  .format(self.attributeName, node, self.name)
                                  ),
            raise
        self.getAllRecursively(query, result)

cdef class NodeBindingRule(BindingRule):
    def attribute(self, attributeName=None, bint shortCut=False):
        return NodeAttribute(self, attributeName, shortCut=shortCut)

    property contents:
        def __get__(self):
            return NodeContents(self)

cdef class __FindNodeOfEdge(NodeBindingRule):
    cdef:
        BindingRule edgeBindingRule
        PNode(*accessNode)(PEdge self)

    def __init__(self, BindingRule edge, bint shortCut=False):
        BindingRule.__init__(self, edge, shortCut=shortCut)
        self.edgeBindingRule = edge

    cdef getAll(self, query, QueryContext result):
        cdef PEdge edge = result.dick[self.edgeBindingRule.name]
        result.dick[self.name] = self.accessNode(edge)
        self.getAllRecursively(query, result)

cdef class FindFromNode(__FindNodeOfEdge):
    def __init__(self, BindingRule edge):
        __FindNodeOfEdge.__init__(self, edge)
        self.accessNode = PEdge.getFromNode

cdef class FindToNode(__FindNodeOfEdge):
    def __init__(self, BindingRule edge):
        __FindNodeOfEdge.__init__(self, edge)
        self.accessNode = PEdge.getToNode

cdef class FindEdge(BindingRule):
    cdef:
        str     edgeKind
        BindingRule    fromNodeBindingRule, toNodeBindingRule
        EdgeDirection edgeDirection

    def __init__(self, *args, **kwargs):
        if len(args) == 3:
            assert len(kwargs) == 0
            kwargs['fromNode'], kwargs['edgeKind'], kwargs['toNode'] = args
        elif len(args) == 1:
            kwargs['edgeKind'], = args
        else:
            raise TypeError('Ambiguous parametrisation.')
        if (kwargs.get('fromNode', None) is None and
            kwargs.get('toNode', None) is None
            ):
                raise NotImplementedError('At least one of fromNode or toNode '
                                          'has tobe specified.')
        self.__init(**kwargs)

    def __init(self, str edgeKind, BindingRule fromNode=None,
               BindingRule toNode=None, bint shortCut=False
               ):
        BindingRule.__init__(self, fromNode, toNode, shortCut=shortCut)
        self.fromNodeBindingRule, self.edgeKind, self.toNodeBindingRule  = \
            fromNode, edgeKind, toNode
        if self.fromNodeBindingRule is not None:
            self.edgeDirection = Out
        elif self.toNodeBindingRule is not None:
            self.edgeDirection = In
        else:
            assert False, "both self.toNodeBindingRule and "\
                "self.fromNodeBindingRule are None!"

    property fromNode:
        def __get__(self):
            return FindFromNode(self)
    property toNode:
        def __get__(self):
            return FindToNode(self)

#         return node.edges(edgeClass, In)
    cdef getAll(self, query, QueryContext result):
        cdef:
            PNode knownNode, otherNode
        if self.fromNodeBindingRule is not None:
            knownNode = result.dick[self.fromNodeBindingRule.name]
            otherNode = (result.dick[self.toNodeBindingRule.name]
                         if self.toNodeBindingRule else None)
        elif self.toNodeBindingRule is not None:
            knownNode = result.dick[self.toNodeBindingRule.name]
            otherNode = None
        else:
            assert False, "both self.toNodeBindingRule and "\
                "self.fromNodeBindingRule are None!"
        cdef Storage storage = query.storage
        cdef:
            EdgeMeta edgeClass = getattr(storage.schema, self.edgeKind)
            PEdge edge
        for edge in knownNode.edges(edgeClass, self.edgeDirection):
            if otherNode is None or edge.getToNode() == otherNode:
                result.dick[self.name] = edge
                self.getAllRecursively(query, result)
