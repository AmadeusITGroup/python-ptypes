from .storage cimport PStructure, PField

cdef class Variable(object):
    cdef:
        readonly str name
        readonly int ordinal


cdef class BindingRule(Variable):
    cdef:
        readonly BindingRule nextBindingRule, prevBindingRule
        bint shortCut
        readonly set usedBindingRules, userBindingRules
        PField keyField  # better name: resultField?

        getAll(BindingRule self, query, QueryContext result)

    cdef inline getAllRecursively(BindingRule self, query,
                                  QueryContext result):
        if self.shortCut and not result.getattr(self.name):
            return
        else:
            if self.nextBindingRule is None:
                result.do()
            else:
                self.nextBindingRule.getAll(query, result)

cdef class QueryContext(object):
    cdef:
        object          query
        object          callback
        readonly dict   dick

        inline setattr(self, name, value):
            self.dick[name] = value

        inline getattr(self, name):
            return self.dick[name]

        set(self, PStructure group, PStructure aggregate)

    cpdef begin(self)
    cdef do(self)
    cpdef end(self)

# class EarlyExit(Exception): pass
