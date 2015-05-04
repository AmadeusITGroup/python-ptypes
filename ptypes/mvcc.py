''' A multi-version concurrency control with commitment ordering.

============
Introduction
============

This module provides multiversion concurrency control via a transaction 
interface. It allows its users to report their read and write accesses (each 
associated with a transaction) to objects called "pages" and guides the users
in creating, using and destroying versions of the pages so that the accesses to
the pages appear to happen as if the transactions had happened serially, one  
after the other, even if in reality they were overlapping in time. In other 
words, it generates a **serializable** history. 

It also ensures **isolation**: none of the transactions (not even aborted ones)
can see the work of any other ongoing transaction. That is, the changes made by 
a transaction becomes visible to others only when the user code performing the 
transaction indicates it has finished its work and reached a consistent state
(by calling ``end()``). The reason for defining isolation this   
way is that a transaction, while in progress, may temporarily violate some  
invariants, causing a potential reader transaction to behave in unexpected ways 
and cause e.g. infinite loops or in the case of transactional memory,  
segmentation faults. Note that isolation as defined this way is different from 
"strictness", which means the transaction has to reach the "committed" state 
before it becomes public.

The module provides the **recoverability** requirement, which demands 
that *committed* transactions do not see the work of uncommitted transactions. 
Since the work of a transaction becomes public before it is actually committed,
recoverability implies that aborts may cascade. 

The module also warrants the **atomicity** of the work of the transactions. 
This means that all of the transactions (even failed ones) see the work of 
any other transaction either wholly or not at all.

The transaction coordinator guarantees **completability**, i.e. that the  
user code of a coordinated transaction can run to completion without being 
blocked or killed. That is, it can keep accessing additional pages as long as 
it wishes. (The transaction may be rolled back after it indicated that its  
work is complete.)

The coordinator guarantees that every page has a linear public history, i.e. a  
precedence relationship can be interpreted between any two *public* versions
of it. (There may be multiple versions being concurrently written by
different transactions, but these versions are private and only one of the
transactions will be allowed to publish its version.)

The isolation and the linear page history requirements together imply that 
at most one of the transactions performing the concurrent writes to the same 
page is published.

Durability is not provided by this module. The users are expected to save 
enough information to be able to replay the events. However some support for
**syncpointing** is provided in order to aid the users in managing the logs. 

==================
Access semantics
==================

The basis for the coordination of the transactions is the identification of 
*precedence* (or "conflict") relationships among them. 
Here "precedence" has a meaning related to the flow of information from one
transaction to the other. This kind of precedence may coincide with the timely 
order of the operations performed by the transactions on the page, but whether 
 this happens is pure luck. Once again: it is *not* the timely order of 
the operations that determines transaction precedence.

The flow of information ("access") is *not* even considered to be  
instantaneous, happening at an atomic moment of time during the transaction,  
so it makes no sense to talk about the order of access events within a 
transaction. In fact, all the (in time dispersed) operations carried out by a 
transaction on a given page are considered to be a single access. An "access" 
lasts for the whole duration of the transaction, from the return of the call
to ``begin()`` till ``end()`` is invoked. 

Regarding the flow of information between the page and the transaction, we 
differentiate the below kinds of accesses:

 * **R - Reads**: The state of the page during and after the transaction is the 
   same as before it. This state may have an influence on the behavior of the 
   transaction.

 * **W - Idempotent writes**: The state of the page before the transaction has 
   *no influence on the behavior of the transaction (not even on the state of 
   the page after the transaction). The update happens in isolation, i.e. 
   transactions other than the one writing the page see the state before the 
   write began.

  * **U - Non-idempotent updates**: The state of the page before the  
   transaction *does influence* the behavior of the transaction (e.g. impacts   
   the state of the page after the transaction). The update happens in  
   isolation, i.e. transactions other than the one writing the page see the  
   state before the write began.

Now we can start defining the precedence relationships among two transactions 
accessing the same page. The precedence depends on the kinds of accesses by the
two transactions.

* **R -- R**: The precedence relationship 
  between two transactions both reading the same page can be chosen 
  arbitrarily, as there is no information flow between the transactions. 

* **UR --> UW**: A transaction T3 reading or non-idempotently updating a page 
  is said to precede a transaction T4 writing or updating that page so that it
  is visible to the outside world if T3 does not see the change T4 caused to 
  the page. (Note that with this definition the precedence relationship
  comes into existence only when the change becomes visible to other 
  transactions.)

* **UW --> RU**: A transaction T1 supplying information to another transaction 
  T2 by T1 writing or non-idempotently updating a page and T2 reading or 
  non-idempotently updating that info from the page is said to precede T2. 

* **W -- W**: If two transactions write to the same page in an 
  idempotent manner, i.e. the state of the page resulting from the write does
  not depend on the state of the page before the write, then the precedence 
  between the two transactions can be arbitrarily chosen (e.g. by satisfying 
  other conflicts in case they exist). Due to the linear page history 
  requirement the precedence has to be decided latest at the time when the new  
  version of the page is made public, i.e. when one of the transactions is 
  committed. 

A transaction T7 is said to succeed a transaction T6 if T6 precedes T7. 

Note that the fact that a transaction Tx does not precede a transaction Ty 
does not imply that Tx succeeds Ty.

======================
Transaction life-cycle
======================

Meta-state private:
    Requests within the context of the transaction to read pages are 
    satisfied by resolving the page to a page version. Update requests are
    resolved to a pair of versions composed of an existing ("accessed") version
    and a newly created one. Each access causes the 
    transaction writing the accessed page version to precede the current 
    transaction (unless the transaction writing that page version is already 
    committed). Each read access causes the transaction superseding the 
    accessed page version to succeed the current transaction, provided there 
    is a transaction superseding the accessed page version and that transaction
    is in a public state. (If the transaction superseding the accessed version
    is in a private state, then the precedence relationship is added when the
    transaction enters a public state.)

    The algorithm selecting the page versions for the access requests   
    guarantees that these precedence relationships never form a cycle.

    Note that a transaction superseding a page version does not succeed the
    transactions reading the superseded page version as long as the superseding
    transaction is private.

Meta-state public:
    Requests to access pages within the context of the transaction are 
    rejected. The page versions created by the transaction are public (i.e. 
    readable by other transactions).

Running:
    Access requests are honored according to the private meta-state.

    A update access to a page version superseded by another transaction causes
    a ``fail()``ure.

    Upon ``fail()`` the transaction enters the failed status.

    Upon ``end()``: 
    If any of the transactions reading the page versions superseded by
    the current transaction succeed the current transaction, then the 
    transaction enters the aborted status. 
    Otherwise the reading transactions are caused to precede the current
    transaction (unless they are already committed) and the current 
    transaction enters the ready status.

Failed:
    Access requests are honored according to the private meta-state.

    Upon entry to this state, if the entry happens because of a preceding 
    transaction being aborted, the pages updated by the aborted transaction are
    eagerly resolved (according to the rules described below) to page versions
    in the context of the transaction entering the failed state. This ensures 
    that the transaction entering the failed state sees all updates the 
    aborted transaction.

    Upon ``end()`` the transaction enters the aborted status.

Ready:

    The transaction stays in this status as long as there is a preceding 
    transaction in a status any other then committed.
    When all preceding transactions are committed, the transaction enter the 
    prepared state.

    Upon ``fail()`` the transaction enters the aborted status .

Prepared:
    Access requests are honored according to the public meta-state.

    Upon entry to this state the local resource manager votes "yes" on the .
    transaction.

    Requests to access pages within the context of the transaction are 
    rejected. The page versions created by the transaction are public (i.e. 
    readable by other transactions).
    After entering this state the local coordinator is not allowed to decide
    about the outcome of the transaction; only the events generated by the 
    global coordinator are respected.

    Upon ``abort()`` the transaction enters the aborted status . (``abort()`` 
    is called by the global transaction coordinator whereas ``fail()`` is 
    a call by the local one.)

    Upon ``commit()`` the transaction enters the committed status . 
    (``commit()`` is called by the global transaction coordinator.)

Committed:
    Access requests are honored according to the public meta-state.

    Upon entry to this state the precedence relationships to the succeeding 
    transactions are removed. (The relationships to the preceding transactions
    were removed while waiting in the ready state.)
    The page versions superseded by the ones written by this transaction are
    discarded.

Aborted:
    This state belongs to neither the public nor the private meta-state.
    Requests to access pages within the context of the transaction are 
    rejected. 

    Before entering this state the access to the page versions created by the 
    aborted transaction is restricted to those transactions that already 
    accessed at least one of these page versions. These transactions are 
    ``fail()``ed. (If they are still in a private state, then they are 
    allowed to complete).

    If an aborted transaction has no successors or its last successor is 
    removed from the precedence graph, then it is also removed from the 
    precedence graph.

==========================
Data structures
==========================

Transactions maintain their life cycle status, their read set (acting as a 
cache mapping the read pages to page versions) and their update set 
(acting as a cache mapping the updated pages to page versions; an update is 
treated as a read until the transaction goes public). They also track the 
transactions preceding and succeeding them in the precedence graph.

Each page tracks the most recent of its public page versions.

A page versions keeps references to the transaction creating it (writer 
transaction), to the ones reading them (reader transactions), and to the 
one publishing the page version superseding it (superseder transaction). 
(Note that the transaction writing the superseding version becomes the 
superseder transaction only when it goes public, if at all.)
The page version also keeps track of the version it was created from 
(previous version).
We define the status of the page version as the life cycle status of the
transaction creating it.

The "previous version" relationship organizes the page versions into a tree.
(When interpreting this relation in the opposite direction, we will say 
"next version"; if the previous of V2 is V1, then V2 is said to be 
"next to" v1.)

The code maintains the following properties of this tree:

 - The tree root is in the committed state and that is the only version in
   that state.
 
 - A prepared page version (if there is one) is next to a committed version.
 
 - A running, failed or ready version is next to a public (committed, 
   prepared  or ready) version.

In other words the public (committed, prepared and ready) versions 
constitute a linear chain. The page the versions in the chain belong to 
updates its reference to the most recent element on this chain 
when a private page version goes public or when a public version enters 
the aborted status. 


==========================
Correctness considerations
==========================

Here is how we meet the requirements:

 * Atomicity: We keep the precedence graph cycle-free (not even non-committed 
     transactions can be part of a cycle). 
     Violating atomicity creates a cycle in the precedence graph, so by 
     avoiding cycles we can guarantee atomicity. 
     When searching for a page version to satisfy an access request, we start
     by selecting its most recent public version. If that was  
     written by a transaction succeeding the one we are working on, we take the  
     next most recent public version. We repeat this until we find a 
     public version that was written by a transaction not succeeding the 
     one we are working on.

     If there is no cycle before the current access, then this algorithm will 
     never create a dependency cycle. This can be proven by the succeeding
     considerations:

      - If the transaction writing the selected page version neither precedes
        nor succeeds the current transaction, then the current access cannot 
        create a cycle (to form a cycle precedence relationships
        generated by at least two accesses are needed). 

      - The transaction writing the selected page version cannot both precede
        and succeed the current transaction, as in that case a dependency cycle
        would already exist even without the current page access.

      - The transaction writing the selected page version does not succeed
        the current transaction because algorithm skips the page versions 
        written by public transactions succeeding it. 

      - The public transaction writing the version superseding the selected 
        one (if any) succeeds the current transaction. (If the superseding 
        public page version did not succeed the current transaction, then that 
        version would have been selected by the algorithm.)

      - If there is no cycle before accessing the selected page version, then
        there will be no cycle after the access. This is because:

         - The transaction writing the selected page version does not succeed
           the current transaction, thus it can precede the current transaction
           without risking a cycle;

         - The public transaction writing the superseding page version (if any)
           already succeeds the current transaction

         - Accessing the selected page version does not imply that
           a transaction writing a superseding version succeeds the current 
           transaction if the transaction writing the superseding 
           version is private. (If the transaction writing the superseding 
           version precedes the current transaction, then the cycle is
           avoided by never making the transaction public, i.e. ``fail()``ing 
           it).
 
      - The algorithm terminates latest when it finds the most recent    
        committed page version, because that page version is public and 
        (because of committing the transactions in the order of their 
        precedence) it cannot succeed the current transaction.

 * Serializability: Theoretically, to ensure this we need to avoid forming  
   precedence cycles from committed transactions. By our cycle-avoidance policy 
   to reach atomicity we automatically ensure serializability

 * Isolation: we keep page versions private until the transaction is ready

 * Recoverability: We do not commit transactions succeeding an aborted one.

 * Linear page history: We do not commit the transaction branching the page 
     history.

 * Completability of transactions:

Created on 2015.04.10.

@author: vadaszd
'''
# When do we remove trx from the precedence graph?
# How do we reconstruct the state of the coordinator after a crash?
from itertools import count

class TryAfter(RuntimeError):
    """ A RuntimeError telling to postpone an operation.

    Raising this exception indicates that a requested operation cannot be 
    performed at the moment but later it may succeed.
    """
    def __init__(self, prevTrxs):
        """
        @param prevTrxs: The transaction that must complete before the
            operation can be successfully retried.
        """
        self.prevTrxs = prevTrxs


class ProtocolError(RuntimeError):
    """ The status of the transaction does not allow the operation requested.

    This usually indicates a programming error. The status of the transaction
    remains unchanged.
    """


class Transaction(object):
    ''' Represents a local resource manager's view on a transaction.
    '''

    # Transaction statuses
    class Status(object):

        @staticmethod
        def enter(trx): 
            trx.status.try2Transit(trx)

        @staticmethod
        def try2Transit(trx):
            pass

    class Private(Status):

        @staticmethod
        def readPage(trx, page,):
            try:
                return trx.readSet[page]
            except KeyError:
                try:
                    return trx.updateSet[page]
                except KeyError:
                    pageVersion = page.resolveAccess(trx)
                    trx.readSet[page] = pageVersion
                    return pageVersion

        # We do not support idempotent writes (all writes are considered 
        # non-idempotent updates).
        @staticmethod
        def updatePage(trx, page):
            try:
                return trx.updateSet[page]
            except KeyError:
                # A new writable page version must be created
                try:
                    initPageVersion = trx.readSet.pop(page)
                except KeyError:
                    initPageVersion = page.resolveAccess(trx)
                initPageVersion.candidateTrxs.add(trx)
                newPageVersion = PageVersion(trx, page, initPageVersion)
                return newPageVersion, initPageVersion

        @staticmethod
        def end(trx): 
            for page, pageVersion in trx.readSet.items():
                if pageVersion.writerTrx is None:
                    del trx.readSet[page]
                    pageVersion.readerTrxs.remove(trx)
                    pageVersion.try2Remove()

        @classmethod
        def _cascadeAbort(self, trx, pages):
            for page in pages:
                self.readPage(trx, page)
            trx.status.fail(trx)

    class Running(Private):
        # can read & write, changes are isolated
        @staticmethod
        def fail(trx):
            trx.transit2(trx.Failed)

        @staticmethod
        def end(trx):
            """ Call this to finish a transaction.

            @return: the status of the transaction after the call.
            """
            trx.Private.end(trx)
            for supersedingVersion in trx.updateSet.values():
                prevPageVersion = supersedingVersion.prevPageVersion
                if prevPageVersion:
                    if prevPageVersion.supersederTrx:
                        trx.fail() # there is another public superseder
                        trx.Failed.end(trx)
                        return trx.status
                    for readerTrx in prevPageVersion.readerTrxs:
                        if readerTrx.doesSucceed(trx):
                            trx.fail()
                            trx.Failed.end(trx)
                            return trx.status
            trx.transit2(trx.Ready)
            return trx.status

    class Failed(Private): 

        @staticmethod
        def fail(trx):
            "Diamond-shapes in the precedence graph may cause double-failures;"
            "the 2nd must be ignored."

        @staticmethod
        def end(trx):
            trx.Private.end(trx)
            trx.transit2(trx.Aborted)
            return trx.status

    class Public(Status):

        @staticmethod
        def _cascadeAbort(trx, updatedPages):
            updatedPages |= trx.updateSet.keys()
            for pageVersion in trx.updateSet.values():
                supersederTrx = pageVersion.supersederTrx
                if supersederTrx:
                    supersederTrx.status._cascadeAbort(supersederTrx, 
                                                       updatedPages)
                for readerTrx in pageVersion.readerTrxs:
                    readerTrx.status._cascadeAbort(readerTrx, updatedPages)
            trx.transit2(trx.Aborted)

    class Ready(Public): 

        @staticmethod
        def fail(trx): 
            trx.status._cascadeAbort(trx, set())

        @staticmethod
        def enter(trx):
            for page, pageVersion in trx.updateSet.items():
                page.latestVersion = pageVersion
                supersededVersion = pageVersion.prevPageVersion
                if supersededVersion is None:
                    continue
                supersededVersion.supersederTrx = trx
                supersededVersion.readerTrxs.remove(trx)
                supersededVersion.candidateTrxs.remove(trx)
                for candidateTrx in supersededVersion.candidateTrxs:
                    candidateTrx.fail()
                supersededVersion.candidateTrxs.clear()
                for readerTrx in supersededVersion.readerTrxs:
                    readerTrx._precedes(trx)
            trx.status.try2Transit(trx)

        @staticmethod
        def try2Transit(trx):
            if all(issubclass(prevTrx.status, (trx.Committed, trx.Failed))
                   for prevTrx in trx.prevTrxs):
                trx.transit2(trx.Prepared)

    class Prepared(Public): 

        @staticmethod
        def enter(trx):
            trx.voteYes()

        @staticmethod
        def abort(trx): 
            trx.status._cascadeAbort(trx, set())

        @staticmethod
        def commit(trx):
            """ Call this to record a commit decision made globally.

            This method has to be called only on distributed transactions,
            after the global coordinator decided to commit the transaction.
            """
            if trx.transactionId is None:
                raise ProtocolError()
            else: 
                trx.transit2(trx.Committed) 

    class Committed(Public): # no more reads & writes, changes are visible outside

        @staticmethod
        def enter(trx):
            trx.committed()
            # remove incoming precedence relationships
            for prevTrx in trx.prevTrxs:
                prevTrx.nextTrxs.remove(trx)
                prevTrx.status.try2Transit(prevTrx)
            trx.prevTrxs.clear()
            # superseded page versions: no new access will happen
            for page, pageVersion in trx.updateSet.items():
                prevPageVersion = pageVersion.prevPageVersion
                if prevPageVersion is None:
                    continue
                assert issubclass(prevPageVersion.writerTrx.status, 
                                  trx.Committed)
                # unlink superseded from its writer trx
                writerTrx = prevPageVersion.writerTrx
                del writerTrx.updateSet[page]
                writerTrx.status.try2Transit(writerTrx)
                prevPageVersion.writerTrx = None
                # unlink superseded from completed reads
                for readerTrx in list(prevPageVersion.readerTrxs):  # use copy
                    if not issubclass(readerTrx.status, trx.Private):
                        del readerTrx.readSet[page]
                        prevPageVersion.readerTrxs.remove(readerTrx)
                        readerTrx.status.try2Transit(readerTrx)
                # unlink from the public chain
                prevPageVersion.supersederTrx = None
                pageVersion.prevPageVersion = None
                # remove version if possible
                prevPageVersion.try2Remove()
            # kick the transactions waiting for our commit
            for nextTrx in list(trx.nextTrxs):  # copy
                if issubclass(nextTrx.status, trx.Ready):
                    nextTrx.status.try2Transit(nextTrx)

        @staticmethod
        def _cascadeAbort(trx, updatedPages):
            assert False, ("Abort cascaded to a committed trx, "
                           "this must not have happened!")

        @staticmethod
        def try2Transit(trx):
            if not trx.nextTrxs and not trx.readSet and not trx.updateSet:
                trx.removed()

    class Aborted(Status): 

        @staticmethod
        def _cascadeAbort(trx, updatedPages):
            "Diamond-shapes in the precedence graph may cause double-aborts;"
            "the 2nd must be ignored."

        @staticmethod
        def enter(trx): 
            for page, pageVersion in trx.updateSet.items():
                prevPageVersion = pageVersion.prevPageVersion
                if prevPageVersion.supersederTrx is trx:
                    prevPageVersion.readerTrxs.add(trx)
                    prevPageVersion.supersederTrx = None
                if page.latestVersion is pageVersion:
                    page.latestVersion = pageVersion.prevPageVersion
            trx.status.try2Transit(trx)

        @staticmethod
        def try2Transit(trx):
            if not trx.nextTrxs:
                for prevTrx in trx.prevTrxs:
                    prevTrx.nextTrxs.remove(trx)
                    prevTrx.status.try2Transit(prevTrx)
                trx.prevTrxs.clear()
                for pageVersion in trx.updateSet.values():
                    pageVersion.writerTrx = None
                    pageVersion.try2Remove()
                    pageVersion.prevPageVersion.readerTrxs.remove(trx)
                    pageVersion.prevPageVersion.try2Remove()
                trx.updateSet.clear()
                for pageVersion in trx.readSet.values():
                    pageVersion.readerTrxs.remove(trx)
                    pageVersion.try2Remove()
                trx.readSet.clear()
                trx.removed()

    trxCounter = count(0)

    def __init__(self, transactionId=None):
        """
        @param transactionId: the ID of the distributed transaction or ``None``
                indicating the transaction is limited to the local resource 
                manager.
        """
        self.transactionId = transactionId
        self.trxNumber = self.trxCounter.next()
        self.readSet = dict()    # PageVersions read but not written, by page
        self.updateSet = dict()  # superseding PageVersions, by page
        self.prevTrxs = set()    # transactions preceding this one
        self.nextTrxs = set()    # transactions this one precedes
        self.transit2(self.Running)

    def __repr__(self):
        return "<{} #{} in status {}>".format(self.__class__.__name__,
                                              self.trxNumber,
                                              self.status.__name__)

    def transit2(self, newStatus):
        self.status = newStatus
        self.status.enter(self)

    def dispatch(methodName):  # @NoSelf
        def event(self, *args, **kwargs):
            return getattr(self.status, methodName)(self, *args, **kwargs)
        return event

    fail =  dispatch('fail')
    readPage = dispatch('readPage')
    updatePage = dispatch('updatePage')
    end = dispatch('end')
    abort = dispatch('abort')
    commit = dispatch('commit')

    def voteYes(self):
        """ A callback to record and communicate the local RM's vote globally.

        Override this method in distributed transactions. The transaction 
        instance will call the overriding method when from a local point of 
        view the transaction can be committed.

        The overriding method must persist the vote and all information 
        necessary to reconstruct the work of the transaction (provided the 
        durability of transactions is a requirement) and communicate the vote
        to the global coordinator.

        Never call this method from the overriding method.
        """
        assert self.transactionId is None, (
            "In distributed RMs this method should be overridden and not "
            "called from the overriding method"
            )
        print self, "has voted YES."
        self.transit2(self.Committed) 

    def committed(self):
        """ You may override this callback method to persist a commit decision.

        If you want your transactions to be durable, you can override this 
        method to persistently record a commit decision.
        The method will be called after a global commit decision is made 
        (for non-distributed transactions the local decision is considered 
        as global).
        """
        print self, "has committed."

    def _precedes(self, other):
        # We are being told that self precedes other. We first check if 
        # a cycle would form by adding this relationship, i.e. 
        # if self succeeds other according to our current knowledge.
        assert other is not self and not self.doesSucceed(other)
        self.nextTrxs.add(other)
        other.prevTrxs.add(self)

    def doesSucceed(self, other):
        # "self is other" is not checked, need to do it separately! 
        if other in self.prevTrxs:
            return True
        else:
            return any( prevTrx.doesSucceed(other) 
                        for prevTrx in self.prevTrxs)

    def removed(self):
        print "Removed", self

    @staticmethod
    def atomic():
        failing = True
        while failing:
            trx = Transaction()
            yield trx
            failing = trx.end() == trx.Aborted

class PagePool(list):
    """ The universe of objects over which transactions operate.
    """

    def __init__(self, numPages):
        for trx in Transaction.atomic():
            list.__init__(self, (Page(trx, i) for i in range(numPages)))
            for page in self:
                pageVersion = page.latestVersion
                pageVersion.readerTrxs.add(trx)
                trx.readSet[page] = pageVersion
#                 pageVersion.candidateTrxs.add(trx)


class Page(object):
    """ Represents the objects accessible to transactions.

    Each Page may exist in several versions. The versions constitute
    a linear history. The version to be used in a particular context is
    determined by the ``resolveAccess()`` method.
    """

    def __init__(self, trx, pageOrdinal, ):
        """ 
        @param trx: the Transaction object creating the page
        @param pageOrdinal: an opaque reference to the entity this 
                object represents
        """
        self.ordinal = pageOrdinal
        self.versionCounter = count(0)
        # The most recent public version of the page.
        self.latestVersion = PageVersion(trx, self, None)

    def __repr__(self):
        return "<{} #{} >".format(self.__class__.__name__,
                                  self.ordinal,)


    def _selectPageVersion(self, trx):
        pageVersion = self.latestVersion
        while pageVersion.writerTrx.doesSucceed(trx):
            pageVersion = pageVersion.prevPageVersion
            assert pageVersion, "Should have found a suitable page version!"
        return pageVersion

    def resolveAccess(self, trx):
        """ Resolve a 
        @param trx: The transaction that will use the page version the page
            is resolved to.
        @return: The page version to be used in the transaction.
        """
        pageVersion = self._selectPageVersion(trx)
        pageVersion.readerTrxs.add(trx)
        # pageVersion.writerTrx does not succeed trx, so no cycle is formed here
        pageVersion.writerTrx._precedes(trx)
        if (pageVersion.supersederTrx is not None and 
                issubclass(pageVersion.supersederTrx.status, trx.Public)):
            # supersederTrx is public, it must already succeed trx
            assert pageVersion.supersederTrx.doesSucceed(trx)
        return pageVersion


class PageVersion(object):
    """ Represents a version of an object accessible to transactions.

    Each time a transaction is about to write a page a new version of it is 
    created. Thus a page version has a single writer transaction. While the 
    writer transaction is private, the page version is inaccessible to
    other transactions. After the writer entered a public state, other 
    transactions may read the page version. The reason is that the set of pages
    written by a transaction may be in an inconsistent state while the 
    transaction is in progress.

    Each page version keeps track of 

    - the transaction writing (creating) it,
    - the transactions reading it
    - the transaction creating a page version superseding it 

    """

    def __init__(self, writerTrx, page, prevPageVersion):
        """ 
        @param writerTrx: the transaction writing the page version
        @param page: the page to which this version belongs
        @param prevPageVersion: the page version self supersedes
        """
        writerTrx.updateSet[page] = self
        self.page = page
        self.versionNumber = page.versionCounter.next()
        self.writerTrx = writerTrx   # the transaction writing the page version
        self.readerTrxs = set()      # transactions reading this page version
        self.prevPageVersion = prevPageVersion
        self.candidateTrxs = set()
        self.supersederTrx = None   # filled in *iff* the superseder is public

    def __repr__(self):
        if self.writerTrx:
            status = self.writerTrx.status.__name__
        else:
            status = 'Obsolete'
        return ("<{} #{}.{} in status {}>"
                .format(self.__class__.__name__,
                        self.page.ordinal, self.versionNumber,
                        status))

    def try2Remove(self):
        if (self.writerTrx is None and
                not self.readerTrxs and
                self.supersederTrx is None):
            self.removed()
            self.page = None

    def removed(self):
        print "Removed", self

if __name__ == "__main__":

    pp = PagePool(5)
    p0 = pp[0]
    t1 = Transaction()
    t2 = Transaction()
    print t1.readPage(p0)
    print t2.readPage(p0)
    print t1.updatePage(p0)
    print t2.updatePage(p0)
    t3 = Transaction()
    print t3.readPage(pp[1])
    print t1.end(), "t1"
    print t3.updatePage(p0)
    t4 = Transaction()
    t5 = Transaction()
    print t4.updatePage(pp[1])
    print t2.end(), "t2"
    print t4.end(), "t4"
    print t5.updatePage(pp[1])
    print t5.end(), "t5"
    print t3.end(), "t3"
