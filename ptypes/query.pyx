# cython: profile=False

from .storage cimport Persistent, Storage
from .storage cimport HashTableMeta, PDefaultHashTable, DefaultDict
from .storage cimport HashEntryMeta, PHashEntry
from .storage cimport StructureMeta, PStructure, PField

import logging
LOG = logging.getLogger(__name__)

from math import log as logarithm
from uuid import uuid4
# from time import strptime, mktime
from collections import defaultdict
from itertools import count

############################  Contingency Table #############################

cdef class PConTable(PDefaultHashTable):

    def __init__(PDefaultHashTable self, unsigned long size):
        PDefaultHashTable.__init__(self, size, )

    cpdef PStructure getAggregate(self, dict dick):

        cdef:
            PField      keyField
            str         key
            StructureMeta groupClass = self.hashEntryClass.keyClass

        # Convert
        d = dict()
        for keyField in groupClass.pfields:
            try:
                key = dick[keyField.name]  # get the key from the result
            except KeyError as e:
                e.args = (e.args[0] + "Candidate fields are " +
                          groupClass.pfields,)
                raise
            d[keyField.name] = key
        return self[groupClass.NamedTupleClass(**d)]

    def rollup(self):
        cdef:
            PStructure   group, aggregate, totalAggregate
            PField      keyField, aggregateField
            StructureMeta groupClass     = self.hashEntryClass.keyClass
            StructureMeta aggregateClass = self.hashEntryClass.valueClass
            PHashEntry  entry
        for keyField in groupClass.pfields:
            for group, aggregate in self.iteritems():
                if keyField.get(group).contents == 'total':
                    continue

                volatileKeyOfTotal = \
                    group.contents._replace({keyField.name: 'total'})

                totalAggregate = self[volatileKeyOfTotal]
                for aggregateField in aggregateClass.pfields:
                    # XXX .add() and .contents() are dynamically resolved
                    aggregateField.get(totalAggregate
                                       ).add(aggregateField.get(aggregate
                                                                ).contents
                                             )

    def entropy(PDefaultHashTable self, str aggregateName, str keyName1,
                str keyName2):
        """ Returns a 6-tuple of estimators for entropy related quantities.

            1st element: Marginal entropy of key1
            2nd element: Marginal entropy of key2
            3rd element: Entropy of the joint distribution of keys 1 and 2
            4th element: The mutual information of keys 1 and 2
            5th element: Conditional entropy of key1 (conditioned on key2)
            6th element: Conditional entropy of key2 (conditioned on key1)

            All values are in bits.
        """
        cdef:
            StructureMeta groupClass     = self.hashEntryClass.keyClass
            StructureMeta aggregateClass = self.hashEntryClass.valueClass
            PStructure   key, value
            PField      keyField
            PField      aggregateField   = getattr(aggregateClass,
                                                   aggregateName)
            dict        d
            PHashEntry  entry
            double      sum12 = 0, sum1 = 0, sum2 = 0, N=-1
            double      natPerBit = logarithm(2)
            double      n, H1, H2, H12
            tuple       non_total_fields = (keyName1, keyName2)
            list        total_fields = list()

        # In any field other than total_fields (i.e. keyName1 and keyName2)
        # we do not find 'total' then we have to skip the entry.
        # If none of keyName1 and keyName2 are 'total', then we add the cell
        # into the running sum of the entropy of the joint distribution.
        # If keyName1 is 'total', then we add the cell into the running sum
        # of the entropy of the marginal distribution of key2 (and vice versa).
        #
        for keyField in groupClass.pfields:
            if keyField.name not in non_total_fields:
                total_fields.append(keyField.name)
        for group, aggregate in self.iteritems():
            d = group.contents
            if any(keyField.get(group).contents != 'total'
                   for keyField in total_fields
                   ):
                continue
            n = aggregateField.get(aggregate).contents
            if getattr(d, keyName1) == 'total':
                if getattr(d, keyName2) == 'total':
                    N = n
                else:
                    sum2 += n*logarithm(n)
            else:
                if getattr(d, keyName2) == 'total':
                    sum1 += n*logarithm(n)
                else:
                    sum12 += n*logarithm(n)
        H1  = (logarithm(N) - sum1  / N) / natPerBit
        H2  = (logarithm(N) - sum2  / N) / natPerBit
        H12 = (logarithm(N) - sum12 / N) / natPerBit
        return (H1, H2, H12, H1+H2-H12, H12-H2, H12-H1)

cdef class ContingencyTable(DefaultDict):
    proxyClass = PConTable

######################  Query Interface ########################
variableOrdinal = count(0)  # XXX The GIL is here used as lock for the ordinal?
cdef class Variable(object):

    def __init__(self, ):
        self.name = '_V' + str(uuid4().hex)
        # XXX Acquire lock/GIL
        self.ordinal = variableOrdinal.next()
        # XXX Release lock/GIL

    def __repr__(self):
        return "{self.name} = {self.__class__.__name__}()".format(self=self)

cdef class BindingRule(Variable):

    # TODO: remove *usedBindingRules
    def __init__(self, *usedBindingRules, bint shortCut=False):
        Variable.__init__(self)
        self.prevBindingRule = self.nextBindingRule = None
        self.shortCut = shortCut
        self.keyField = None
        self.usedBindingRules = set(usedBindingRule
                                    for usedBindingRule in usedBindingRules
                                    if usedBindingRule)
        self.userBindingRules = set()
        for bindingRule in self.usedBindingRules:
            (<BindingRule>bindingRule).userBindingRules.add(self)

    def walk(self, walked):
        if self in walked:
            return
        walked.add(self)
        for bindingRule in self.userBindingRules | self.usedBindingRules:
            bindingRule.walk(walked)

    # XXX sort out the confusion here:
    # - In Query definitions, a RichCompare object needs to be returned,
    #     postponing evaluation until query-runtime, and comparing
    #     the values assigned to the bindingRule in that iteration
    # - When the bindingRule chain is assembled, we must be able to compare
    #     bindingRule objects for identity (== and !=) immediately
    #     def __richcmp__(BindingRule self, other, int op):
    #         return RichCompare(self, other, op)

    cdef getAll(BindingRule self, query, QueryContext result):
        """ This method must be overridden in derived classes.
            BindingRules that may be first bindingRules (e.g. Each and Param)
            should define it as cpdef, so that it is callable from Python as
            well. For other bindingRules, cdef is enough.
        """
        raise NotImplementedError(self)

    def attribute(self, attributeName=None, bint shortCut=False):
        return Attribute(self, attributeName, shortCut=shortCut)

    property contents:
        def __get__(self):
            return Contents(self)


class EarlyExit(Exception):
    pass

cdef class SubQuery(BindingRule):
    cdef:
        BindingRule firstBindingRule, predicate

    def __init__(self, BindingRule firstBindingRule, BindingRule predicate,
                 bint shortCut=False
                 ):
        BindingRule.__init__(self, firstBindingRule, predicate,
                             shortCut=shortCut)
        self.firstBindingRule = firstBindingRule
        self.predicate = predicate

    cdef getAll(self, query, QueryContext result):
        subQueryContext = QueryContext(None, self.callback(result))
        subQueryContext.dick = result.dick.copy()
        subQueryContext.begin()
        try:
            self.firstBindingRule.getAll(self, subQueryContext)
        except EarlyExit:
            pass
        self.getAllRecursively(query, result)

    def callback(SubQuery self, result):
        # cannot be a cdef function - yield is not allowed in cdef
        raise NotImplementedError(self)
        # not reachable, but turns it into a generator
        # yield


cdef class Any(SubQuery):
    def callback(Any self, result):
        try:
            while True:
                subQueryContext = yield
                self.predicate.getAll(self, subQueryContext)
                if result.getattr(self.predicate.name):
                    result.setattr(self.name, True)
                    raise EarlyExit()
        except StopIteration:
            result.setattr(self.name, False)


cdef enum ComparisonOperator:
    LT=0, LE, EQ, NE, GT, GE


cdef class RichCompare(BindingRule):
    """ Bind the result of a comparison to the name of the rule.
    """
    cdef:
        BindingRule oneBindingRule
        object other
        int op

    def __init__(RichCompare self, BindingRule oneBindingRule, other,
                 ComparisonOperator op, bint shortCut=False):
        if isinstance(other, BindingRule):
            BindingRule.__init__(self, oneBindingRule, other,
                                 shortCut=shortCut)
        else:
            BindingRule.__init__(self, oneBindingRule, shortCut=shortCut)
        self.oneBindingRule = oneBindingRule
        self.other = other
        self.op = op
        assert op in (2, 3), self.op  # only == and != are supported

    cdef getAll(RichCompare self, query, QueryContext result):
        oneValue = result.getattr(self.oneBindingRule.name)
        if isinstance(self.other, BindingRule):
            otherValue = result.getattr(<BindingRule>(self.other).name)
        else:
            otherValue = self.other
        if isinstance(oneValue, Persistent):
            if not isinstance(otherValue, Persistent):
                oneValue = oneValue.contents
        else:
            if isinstance(otherValue, Persistent):
                otherValue = otherValue.contents

        if self.op==EQ:
            rv = oneValue == otherValue
        elif self.op==NE:
            rv = oneValue != otherValue
        else:
            assert False, self.op  # only == and != are supported
#         if op==LT: return self.offset  < other.offset
#         if op==LE: return self.offset <= other.offset
#         if op==GT: return self.offset  > other.offset
#         if op==GE: return self.offset >= other.offset
        result.setattr(self.name, rv)
        self.getAllRecursively(query, result)

# cpdef RichCompare LessThan(BindingRule oneBindingRule, other, shortCut):
#    return RichCompare(oneBindingRule, other, LT, shortCut)
# cpdef RichCompare LessOrEqual(BindingRule oneBindingRule, other, shortCut):
#     return RichCompare(oneBindingRule, other, LE, shortCut)
cpdef RichCompare Equal(BindingRule oneBindingRule, other, shortCut):
    return RichCompare(oneBindingRule, other, EQ, shortCut)

cpdef RichCompare NotEqual(BindingRule oneBindingRule, other, shortCut):
    return RichCompare(oneBindingRule, other, NE, shortCut)

# cpdef RichCompare GreaterThan(BindingRule oneBindingRule, other, shortCut):
#     return RichCompare(oneBindingRule, other, GT, shortCut)
# cpdef RichCompare GreaterOrEqueal(BindingRule oneBindingRule, other,
#                                    shortCut):
#     return RichCompare(oneBindingRule, other, GE, shortCut)


cdef class Constant(BindingRule):
    """ Bind an interned constant value to the name of the rule.
    """
    cdef:
        readonly str typ
        readonly value

    def __init__(self, value, typ=None, bint shortCut=False):
        BindingRule.__init__(self, shortCut=shortCut)
        self.value = value
        if typ is None:
            self.typ = ("string" if isinstance(value, str) else None)
        else:
            self.typ = typ

    cpdef getAll(self, query, QueryContext result):
        try:
            value = query.storage.internValue(self.typ, self.value)
        except ValueError as e:
            e.args = ("Could not intern the value for constant '{0}'"
                      .format(self.name),) + e.args
            raise
        result.setattr(self.name, value)
        self.getAllRecursively(query, result)


cdef class Param(BindingRule):
    """ Bind the interned value of a query parameter to the name of the rule.
    """
    cdef:
        readonly str typ, description

    def __init__(self, typ='string', name=None, description="",
                 bint shortCut=False):
        BindingRule.__init__(self, shortCut=shortCut)
        self.name = name
        self.typ = typ
        self.description = description

    cpdef getAll(self, query, QueryContext result):
        try:
            value = query.storage.internValue(self.typ,
                                              query.paramValues[self.name])
        except ValueError as e:
            e.args = ("Could not intern the value for parameter '{0}'"
                      .format(self.name),) + e.args
            raise
        result.setattr(self.name, value)
        self.getAllRecursively(query, result)


cdef class LookUp(BindingRule):
    cdef:
        str indexName
        BindingRule keyBindingRule

    def __init__(self, str indexName, BindingRule key, bint shortCut=False):
        BindingRule.__init__(self, key, shortCut=shortCut)
        self.indexName, self.keyBindingRule = indexName, key

    cdef getAll(self, query, QueryContext result):
        idx = getattr(query.storage.root, self.indexName)
        key = result.dick[self.keyBindingRule.name]
        value = idx[key]
        result.setattr(self.name, value)
        self.getAllRecursively(query, result)


cdef class Each(BindingRule):
    """ Bind the next value in a hash index to the name of the rule.
    """
    cdef readonly str indexName

    def __init__(self, str indexName, bint shortCut=False):
        BindingRule.__init__(self, shortCut=shortCut)
        self.indexName = indexName

    cpdef getAll(Each self, query, QueryContext result):
        idx = getattr(query.storage.root, self.indexName)
        for value in idx.itervalues():
            result.setattr(self.name, value)
            self.getAllRecursively(query, result)


cdef class Attribute(BindingRule):
    """ Bind the value of an attribute of an object to the name of the rule.
    """
    cdef:
        readonly str attributeName
        BindingRule bindingRule

    def __init__(self, BindingRule bindingRule, str attributeName=None,
                 bint shortCut=False):
        BindingRule.__init__(self, bindingRule, shortCut=shortCut)
        self.bindingRule = bindingRule
        self.attributeName = attributeName

    cdef getAll(self, query, QueryContext result):
        cdef Persistent persistent = result.getattr(self.bindingRule.name)
        try:
            attributeValue = getattr(persistent,
                                     self.attributeName or self.name)
            result.setattr(self.name, attributeValue)
        except Exception as e:
            e.args = e.args[0] + (" while accessing attribute '{0}' of {1} "
                                  "in bindingRule '{2}'"
                                  .format(self.attributeName, persistent,
                                          self.name)
                                  ),
            raise
        self.getAllRecursively(query, result)


cdef class Contents(BindingRule):
    """ Bind the contents of a node to the name of the rule.
    """
    cdef:
        BindingRule bindingRule

    def __init__(self, BindingRule bindingRule, bint shortCut=False):
        BindingRule.__init__(self, bindingRule, shortCut=shortCut)
        self.bindingRule = bindingRule

    cdef getAll(self, query, QueryContext result):
        cdef Persistent persistent = result.getattr(self.bindingRule.name)
        try:
            result.setattr(self.name, persistent.contents)  # XXX performance
        except Exception as e:
            e.args = e.args[0] + (" while accessing the contents of {0} in "
                                  "bindingRule '{1}'"
                                  .format(persistent, self.name)
                                  ),
            raise
        self.getAllRecursively(query, result)


def printQueryContexts():
    try:
        while True:
            print (yield)
    except StopIteration:
        pass


def noOp():
    try:
        while True:
            yield
    except StopIteration:
        pass

cdef class QueryContext(object):

    def __init__(self, query=None, callback=None):
        self.query = query
        self.callback = callback if callback else noOp()
        self.dick = dict()

    def __repr__(self):
        return ', '.join(list(('{0} = {1}'.format(k, self.dick[k])
                               for k in sorted(self.dick)
                               if not k.startswith('_')
                               )))

#     def saveState(self):
#         cdef list result = list()
#         for bindingRule in self.query.bindingRules:
#             try:
#                 value = self.dick[(<BindingRule>bindingRule).name]
#             except KeyError:
#                 continue
#             else:
#                 result.append(value)
#         return tuple( result)

    def __getattr__(self, name):
        return self.getattr(name)

    cdef set(self, PStructure group, PStructure aggregate):
        cdef Aggregator aggregator
        cdef BindingRule keyBindingRule
        for aggregator in self.query.aggregators:
            self.dick[aggregator.name] = \
                aggregator.aggregateField.get(aggregate)

        for keyBindingRule in self.query.GroupBy:
            self.dick[keyBindingRule.name] = \
                keyBindingRule.keyField.get(group)

    cpdef begin(self):
        self.callback.next()

    cdef do(self):
        self.callback.send(self)

    cpdef end(self):
        self.callback.close()

cdef class AggregatingQueryContext(QueryContext):
    cdef:
        PConTable contingencyTable
        set aggregators

    def __init__(self, query, PConTable contingencyTable):
        QueryContext.__init__(self, query, None)
        self.contingencyTable = contingencyTable
        self.aggregators = query.aggregators

    def begin(self):
        pass

    cdef do(self):
        cdef:
            PStructure aggregate = \
                self.contingencyTable.getAggregate(self.dick)
            Aggregator aggregator

        for aggregator in self.aggregators:
            aggregator.aggregate(aggregate, self)

    def end(self):
        self.contingencyTable.rollup()

cdef class Aggregator(Variable):
    cdef:
        BindingRule bindingRule
        tuple bindingRules
        object memory
        PField aggregateField  # resultField ?

    def __init__(self, *bindingRules):
        # XXX why not init the base class?
        self.aggregateField = None
#         self.distinct = kwargs.get('distinct', False)
        for bindingRule in bindingRules:
            assert isinstance(bindingRule, BindingRule), bindingRule
        self.bindingRule = bindingRules[0] if bindingRules else None
        self.bindingRules = bindingRules
        self.memory = defaultdict(set)

    def reset(self, result):
        result.dick[self.name] = self.accumulatorClass()

    cdef aggregate(self, PStructure aggregate,
                   AggregatingQueryContext aggregatingQueryContext
                   ):
        return self.doAggregate(aggregate, aggregatingQueryContext)

    cdef doAggregate(self, PStructure aggregate,
                     AggregatingQueryContext aggregatingQueryContext
                     ):
        raise NotImplementedError

# cdef class Distinct(object):
#     cdef aggregate(self, PStructure aggregate,
#                     AggregatingQueryContext aggregatingQueryContext):
#         rolledUpQueryContextState = aggregate.saveState()
#         rollingQueryContextState = tuple(getattr(aggregatingQueryContext,
#                 (<BindingRule>bindingRule).name)
#                 for bindingRule in self.bindingRules)
#         memory = self.memory[rolledUpQueryContextState]
#         if rollingQueryContextState in memory: return
#         memory.add(rollingQueryContextState)
#         self.doAggregate(aggregate, aggregatingQueryContext)

# class Unique(Aggregator):
#     accumulatorClass = set
#
#     cdef doAggregate(self, PStructure aggregate,
#                     AggregatingQueryContext aggregatingQueryContext):
#         value = tuple(getattr(aggregatingQueryContext,
#                     (<BindingRule>bindingRule).name)
#                     for bindingRule in self.bindingRules) # XXX optimize
#         self.aggregateField.get(aggregate).add(value)

cdef class AggregatorOf1(Aggregator):
    def __init__(self, bindingRule):
        Aggregator.__init__(self, bindingRule, )

cdef class Count(AggregatorOf1):
    accumulatorClass = int

    cdef doAggregate(self, PStructure aggregate,
                     AggregatingQueryContext aggregatingQueryContext
                     ):
        # XXX .inc is dynamically resolved
        self.aggregateField.get(aggregate).inc()

# class CountDistinct(Distinct, Count): pass # base class order matters!

cdef class Sum(AggregatorOf1):
    accumulatorClass = int

    cdef doAggregate(self, PStructure aggregate,
                     AggregatingQueryContext aggregatingQueryContext
                     ):
        self.bindingRule.aggregateField.get(aggregate)\
            .add(aggregatingQueryContext.dick[self.bindingRule.name])


class QueryMeta(type):

    def __new__(meta, class_name, bases, attribute_dict):  # @NoSelf

        GroupBy = attribute_dict.get('GroupBy', ())
        assert isinstance(GroupBy, (tuple, list))

        attribute_dict['GroupBy'] = GroupBy
        attribute_dict['parameters'] = parameters      = list()
        attribute_dict['parameterNames'] = parameterNames  = set()
        attribute_dict['lookups'] = lookups         = set()
        attribute_dict['aggregators'] = aggregators     = set()

        bindingRules = set()
        for k, v in attribute_dict.items():
            if isinstance(v, Variable):
                (<Variable>v).name = k
            if isinstance(v, BindingRule):
                bindingRules.add(v)
            if isinstance(v, (Param,)):
                parameterNames.add(k)
                parameters.append(v)
            if isinstance(v, (LookUp,)):
                lookups.add(k)
            if isinstance(v, (Aggregator,)):
                aggregators.add(v)
        parameters.sort(key=Param.ordinal.__get__)
        cdef:
            BindingRule bindingRule
            Aggregator aggregator
        if GroupBy:
            output2 = attribute_dict['output2']  # output storage
            # we only support blank storages for now
            assert output2.createTypes
            attributes = dict(__metaclass__=StructureMeta,
                              storage=output2
                              )
            for bindingRule in GroupBy:
                assert isinstance(bindingRule, BindingRule), bindingRule
                attributes[bindingRule.name] = output2.schema.String
            GroupClass = StructureMeta('Group', (PStructure,), attributes)
            for bindingRule in GroupBy:
                bindingRule.keyField =\
                    <PField?> getattr(GroupClass, bindingRule.name)

            attributes = dict(__metaclass__=StructureMeta,
                              storage=output2
                              )
            for aggregator in aggregators:
                attributes[aggregator.name] = output2.schema.Int
            AggregateClass = StructureMeta('Aggregate', (PStructure,),
                                           attributes)
            for aggregator in aggregators:
                aggregator.aggregateField =\
                    <PField?> getattr(AggregateClass, aggregator.name)

            _                = HashEntryMeta._typedef(output2,
                                                     'ContingencyCell',
                                                     PHashEntry,
                                                     'Group',
                                                     'Aggregate')
            ContingencyTable = HashTableMeta._typedef(output2,
                                                     'ContingencyTable',
                                                     PConTable,
                                                     'ContingencyCell')
            attribute_dict['Group'] = GroupClass
            attribute_dict['Aggregate'] = AggregateClass
            attribute_dict['ContingencyTable'] = ContingencyTable

        klass = type.__new__(meta, class_name, bases, attribute_dict)
        klass.__orderBindingRules(bindingRules)
        return klass

    def __orderBindingRules(klass, startPoints):  # @NoSelf #startPoints
        bindingRules = set()
        for startPoint in startPoints:  # iterate over a copy
            startPoint.walk(bindingRules)
        klass.bindingRules = sorted(bindingRules, key=Param.ordinal.__get__)
        klass.firstBindingRule = \
            klass.bindingRules[0] if klass.bindingRules else None

        numberOfBindingRules = len(klass.bindingRules)
        cdef BindingRule bindingRule
        for i in range(numberOfBindingRules):
            bindingRule = klass.bindingRules[i]
            bindingRule.prevBindingRule = \
                klass.bindingRules[i-1] if i   > 0 else None

            bindingRule.nextBindingRule = \
                klass.bindingRules[i+1] if i+1 < numberOfBindingRules else None


class Query(object):

    """ Selects combinations of persistent objects.

        Each selected combination is sent to a generator.

        Treat this as an abstract base class and define your queries in
        subclasses derived from this. Specify the binding rules in the body of
        the class and override the ``processOne()`` method.
    """
    __metaclass__ = QueryMeta

    def __init__(self, Storage storage, **paramValues):
        """ Initialize the query

            @param storage:
        """
        self.storage = storage
        paramValueNames = set(paramValues)
        unInitializedParameters = self.parameterNames - paramValueNames
        unusedParameters = paramValueNames - self.parameterNames
        if unInitializedParameters:
            raise TypeError('Uninitialised query parameters: {p}'
                            .format(p=' ,'.join(sorted(unInitializedParameters)
                                                )
                                    )
                            )
        if unusedParameters:
            raise TypeError('Unused query parameters: {p}'
                            .format(p=' ,'.join(sorted(unusedParameters))))
        self.paramValues = paramValues

    def __call__(self, QueryContext context=None, callback=None,
                 unsigned long numCellsInContingencyTable=10000
                 ):
        """ Enumerate the object-combinations matching the binding rules.

            Each selected combination is sent to the ``processOne()``
            generator.

            @param context: An optional QueryContext instance that will be used
                            for the enumaration & callbacks. If missing, a
                            QueryContext instance will be internally created
                            and used.
            @param callback: An optional generator function to which the
                            combinations will be sent. If missing,
                            ``self.processOne()`` is going to be used.
        """
        if callback is None:
            callback =  self.processOne
        if context is None:
            context = QueryContext(self, callback())
        context.query = self
        if self.GroupBy:
            self.contingencyTable = \
                self.ContingencyTable(numCellsInContingencyTable)
            runningQueryContext = \
                AggregatingQueryContext(self, self.contingencyTable)
        else:
            runningQueryContext = context
        runningQueryContext.begin()
        self.firstBindingRule.getAll(self, runningQueryContext)
        runningQueryContext.end()
        if self.GroupBy:
            context.begin()
            for entry in self.contingencyTable.iterEntries():
                context.set(entry.key, entry.value)
                context.do()
            context.end()

    def processOne(self):
        """ A generator to which the query context is repeatedly sent.

            Whenever the query context reaches a state matching all the binding
            rules, it is sent to this generator.

            This generator method can be overridden in derived classes.
            The default implementation prints a header and trailer
            and in between the context every time it receives it.
        """
        print '==== Results ===='
        try:
            while True:
                print (yield)
        except GeneratorExit:
            pass
        print '---- End of results ----'

    @staticmethod
    def consolidate(queries):
        pass
