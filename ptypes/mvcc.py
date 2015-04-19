''' A transaction coordinator obeying the commitment ordering principle.

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
a transaction becomes visible to others only when the transaction reaches the  
*ready* state (by calling ``end()``). The reason for defining isolation this   
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
This means that all of the transactions (even aborted ones) see the work of 
any other transaction either wholly or not at all.

Optionally, the transaction coordinator can guarantee that the coordinated 
transactions can run to completion. That is, they can keep accessing additional
pages as long as they wish, regardless of the generated (potentially circular)
dependencies.

The coordinator guarantees that every page has a linear commit history, i.e. a  
precedence relationship can be interpreted between any two *committed* versions
of it. 

The isolation and the linear page history requirements together imply that 
either 

  * concurrent write requests to the same page are prevented (blocked) or
  
  * at most one of the transactions performing the concurrent write requests 
     is committed

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
  is said to precede a transaction T4 writing or updating that page if T3 
  does not see the change T4 caused to the page.

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

A transaction T7 is said to follow a transaction T6 if T6 precedes T7. 

Note that the fact that a transaction Tx does not precede a transaction Ty 
does not imply that Tx follows Ty.

==========================
Correctness considerations
==========================

Here is how we meet the requirements:

 * Atomicity: We keep the precedence graph cycle-free (not even non-committed 
     transactions can be part of a cycle). 
     Violating atomicity creates a cycle in the precedence graph, so by 
     avoiding cycles we can guarantee atomicity. 
     We keep the versions of a page in a list in the order they are created. 
     In the creation order ready or running versions are always more recent 
     than committed ones. When searching for a page version to satisfy an 
     access request, we use the following algorithm: We start by selecting the 
     most recent version. If that is running or failed, or was written by a 
     transaction following the one we are working on, we take the next most 
     recent. We repeat this until we find a public version that was 
     written by a transaction not following the one we are working on.
     If there is no cycle before the current access, then this algorithm will 
     never create a dependency cycle. This can be proven by the following
     considerations:

      - If the transaction writing the selected page version neither precedes
        nor follows the current transaction, then a single access cannot create
        a cycle. 

      - The algorithm trivially avoids forming cycles with transactions 
        following the current one. 

      - The transaction writing the selected page version cannot both precede
        and follow the current transaction, as in that case a dependency cycle
        would already exist even without the current page access.

      - To form a cycle with a preceding transaction, the current
        transaction would need to access a page version superseded by the 
        preceding transaction. However, since the algorithm checks the page  
        versions in reverse creation order, the superseding version will be 
        checked before the superseded one. The superseding version will be 
        accepted by the algorithm because it was written by a transaction 
        preceding the current one and thus it is public and (in absence of a 
        cycle existing before the current access) cannot follow the 
        current transaction.

      - The algorithm terminates latest when it finds the most recent    
        committed page version, because that page version is public and 
        (because of committing the transactions in the order of their 
        precedence) it cannot follow the current transaction.

 * Serializability: Theoretically, to ensure this we need to avoid forming  
   precedence cycles from committed transactions. By our cycle-avoidance policy 
   to reach atomicity we automatically ensure serializability

 * Isolation: we keep page versions private until the transaction is ready

 * Recoverability: We do not commit transactions following an aborted one.

 * Linear page history: We do not commit the transaction branching the page 
     history.

 * Completability of transactions:

Created on 2015.04.10.

@author: vadaszd
'''

# How can we keep the precedence graph cycle-free without interrupting transactions?
# When do we remove trx from the precedence graph?
# How do we reconstruct the state of the coordinator after a crash?

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


class ConflictError(RuntimeError):
    """ The operation resulted in a dependency cycle.

    The transaction involved will not commit. The transaction still needs to be
    ``end()``ed so that its resources are freed.
    """


class ProtocolError(RuntimeError):
    """ The status of the transaction does not allow the operation requested.

    This usually indicates a programming error. The status of the transaction
    remains unchanged.
    """


class Transaction(object):
    ''' Represents a local resource manager's view on a transaction.
    '''

    # Transaction statuses
    (RUNNING,    # can read & write, changes are isolated
     FAILED,    # like above, commit will fail 
     READY,      # no writes, changes are visible, pending on other commits
     PREPARED,   # locally decided to commit; pending on global commit decision
     COMMITTED   # no more reads & writes, changes are visible outside
     ) = range(1, 6)

    def __init__(self, transactionId=None):
        """
        @param transactionId: the ID of the distributed transaction or ``None``
                indicating the transaction is limited to the local resource 
                manager.
        """
        self.transactionId = transactionId
        self.readSet = dict()    # PageVersions read but not written, by page
        self.updateSet = dict()  # PageVersions read and/or written, by page
        self.prevTrxs = set()    # transactions preceding this one
        self.nextTrxs = set()    # transactions this one precedes
        self.status = self.RUNNING

    def abort(self): 
        # The failure of a transaction must be propagated along the conflict 
        # graph as soon as possible to avoid work that anyway will be thrown 
        # away. 
        self.status = self.FAILED
        for trx in self.nextTrxs:
            trx.abort()

    def readPage(self, page, doForce=False):
        try:
            return self.readSet[page]
        except KeyError:
            try:
                return self.updateSet[page]
            except KeyError:
                pageVersion = page.resolveRead(self, doForce)
                self.readSet[page] = pageVersion
                return pageVersion

    # We do not support idempotent writes (all writes are considered 
    # non-idempotent updates).
    def updatePage(self, page, doForce=False):
        try:
            return self.updateSet[page]
        except KeyError:
            # A new writable page version must be created
            newPageVersion, initPageVersion = \
                                    page.resolveUpdate(self, doForce)
            try:
                readPageVersion = self.readSet.pop(page)
            except KeyError:
                return newPageVersion, initPageVersion
            else:
                # The page we want to write is already read by the trx.
                # The new writable page version must initialized from the  
                # read one.
                if initPageVersion is readPageVersion:
                    return newPageVersion, readPageVersion
                else:
                    # We cannot initialize the new page version from the
                    # one already seen by the trx.
                    # XXX Should the precedence be removed now?
                    if doForce:
                        self.status = self.FAILED
                        return newPageVersion, readPageVersion
                    else:
                        raise ConflictError()

    def end(self): 
        """ Call this to finish a transaction.

        Can be called repeatedly.
        @raise TryAfter: there are some other transactions that need to
               commit before this one.
        @return: the status of the transaction after the call.
        """
        if self.status == self.READY:
            if any(prevTrx.status != self.COMMITTED 
                                            for prevTrx  in self.prevTrxs):
                raise TryAfter(xxx)
            else:
                self.status = self.PREPARED
                self.voteYes()
        elif self.status == self.RUNNING:
            # any failed transactions should have caused us to fail already
            assert not any(prevTrx.status == Transaction.FAILED 
                                            for prevTrx  in self.prevTrxs)
            self.status = self.READY
            self.end()
        elif self.status == Transaction.FAILED:
            cleanUp
        elif self.status in (Transaction.PREPARED, Transaction.COMMITTED):
            pass
        return self.status

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
        self.__commit()

    def commit(self):
        """ Call this to record a commit decision made globally.

        This method has to be called only on distributed transactions,
        after the global coordinator decided to commit the transaction.
        """
        if self.transactionId is None:
            raise ProtocolError()
        else: 
            self.__commit()

    def __commit(self):
        if self.status == self.PREPARED:
                self.status = self.COMMITTED
                self.committed()
                cleanup
        else:
            raise ProtocolError()

    def committed(self):
        """ You may override this callback method to persist a commit decision.

        If you want your transactions to be durable, you can override this 
        method to persistently record a commit decision.
        The method will be called after a global commit decision is made 
        (for non-distributed transactions the local decision is considered 
        as global).
        """

    def __enter__(self): pass
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            self.abort()
        self.end()
        return False

    def _precedes(self, other):
        # We are being told that self precedes other. We first check if 
        # a cycle would form by adding this relationship, i.e. 
        # if other precedes self according to our current knowledge.
        if other is self or self._doesFollow(other):
            raise ConflictError() 
        self.nextTrxs.add(other)
        other.prevTrxs.add(self)

    def _doesFollow(self, other):
        # "self is other" is not checked, need to do it separately! 
        if other in self.prevTrxs:
            return True
        else:
            return any( prevTrx._doesFollow(other) 
                        for prevTrx in self.prevTrxs)


class PagePool(list):
    """ The universe of objects over which transactions operate.
    """

    def __init__(self, numPages):
        with Transaction() as trx:
            list.__init__(Page(trx, i) for i in range(numPages))


class Page(object):
    """ Represents the objects accessible to transactions.

    Each object may exist in several versions. The versions constitute
    a linear history. The version to be used in a particular context is
    determined by the ``resolveRead()`` and the ``resolveUpdate()`` methods.
    """

    def __init__(self, trx, pageOrdinal, ):
        """ 
        @param trx: the Transaction object creating the page
        @param pageOrdinal: an opaque reference to the entity this 
                object represents
        """
        self.ordinal = pageOrdinal
        self.versions = list()   # The versions of the page we know about.
        self.versions.append(PageVersion(trx, self))

    def resolveRead(self, trx, doForce):
        """
        @param trx: The transaction that will use the page version the page
            is resolved to.
        @param doForce: Return a new page version even if that would violate
            the consistency rules. In the case when the violation would
            actually happen the transaction is failed, so that the violation 
            does not become visible. Default is ``False``. Not yet in use.
        @return: The page version to be used in the transaction.
        @raise TryAfter: Future version of this software may raise
            this exception when doForce is ``False`` and a violation would 
            take place. 
        """
        # There can be at most 1 not-yet-failed-or-aborted transaction writing 
        # a page version and it must be *after* the last committed one. (why?)
        writingTrx = None   
        # For now we return the latest committed version
        for pageVersion in reversed(self.versions):
            if pageVersion.writerTrx.status == Transaction.RUNNING:
                writingTrx = pageVersion.writerTrx
            # A transaction may violate invariants while in progress, therefore 
            # its updates are isolated while it is in the RUNNING status.
            # The invariants must satisfied by the time it decides to commit, 
            # so the updates are made visible already in the READY status.
            if pageVersion.writerTrx.status in (Transaction.READY,
                                                Transaction.COMMITTED,
                                                Transaction.PREPARED):
                # The page version will not change any more
                pageVersion.readerTrxs.add(trx)
                try:
                    pageVersion.writeTrx._precedes(trx)
                    if writingTrx is not None:
                        trx._precedes(writingTrx)
                except ConflictError:
                    if doForce:
                        trx.abort()
                        # XXX How can we be sure that pageVersion is consistent
                        # with the other pages seen by the transaction?
                    else:
                        raise
                return pageVersion
        assert False, "There must be a committed page version!"

    def resolveUpdate(self, trx, doForce):
        """ Resolve the page to a page version for the given transaction.

        @param trx: The transaction that will use the page version the page
            is resolved to.
        @param doForce: Return a new page version even if that would diverge
            the history of the page. In the case when the diversion would 
            actually happen the transaction is failed, so that the diversion 
            does not become visible.
        @return: A 2-tuple of page versions; the 1st is a newly created page
            version, it has to be initialized from the 2nd one.
        @raise TryAfter: This exception is raised when doForce is
            ``False`` and a diversion would take place. 
        """
        newPageVersion = PageVersion(trx, self)
        for pageVersion in reversed(self.versions):
            if pageVersion.writerTrx.status in (Transaction.READY,
                                                Transaction.COMMITTED,
                                                Transaction.PREPARED):
                # The page version will not change any more
                # so the history of the page will not diverge if we create 
                # a new page version here. Just need to find a way to init it.
                try:
                    pageVersion.writeTrx._precedes(trx)
                    for readerTrx in pageVersion.readerTrxs:
                        readerTrx._precedes(trx)
                except ConflictError:
                    trx.abort()
                    if doForce:
                        pass
                    else:
                        raise
                self.versions.append(newPageVersion)
                return newPageVersion, pageVersion, 
            elif pageVersion.writerTrx.status == Transaction.FAILED:
                # The page version is isolated and will be discarded
                # so we have to ignore it
                continue
            assert pageVersion.writerTrx.status == Transaction.RUNNING
            # A second update is attempted while the first one is still
            # in progress. This would result in a diverging page history
            # so we need to prevent it.
            trx.abort()
            if doForce:
                # We prevent it by failing the transaction but letting it 
                # proceed. For that we need the latest consistent page version.
                for pageVersion2 in reversed(self.versions):
                    if pageVersion2.writerTrx.status in (Transaction.READY,
                                                         Transaction.COMMITTED, 
                                                         Transaction.PREPARED):
                        break
                else:
                    assert False, "There must be a committed page version!"
#                 pageVersion2.writeTrx._precedes(trx)
#                 for readerTrx in pageVersion2.readerTrxs:
#                     readerTrx._precedes(trx)

                # XXX How can we be sure that pageVersion2 is consistent
                # with the other pages seen by the transaction?
                self.versions.append(newPageVersion)
                return newPageVersion, pageVersion2
            else:
                # We prevent it by making the trx wait for the 1st one to
                # finish
                raise TryAfter(set(pageVersion.writerTrx))
        assert False, "There must be a committed page version!"


class PageVersion(object):
    """ Represents a version of an object accessible to transactions.

    Each time a transaction is about to write a page a new version of it is 
    created. Thus a page version has a single writer transaction. While the 
    writer transaction is in progress, the page version is inaccessible to
    other transactions. After the writer is prepared or committed, other 
    transactions may read the page version. The reason is that the set of pages
    written by a transaction may be in an inconsistent state while the 
    transaction is in progress.

    A page version is deleted from the page when 

     * it is not being written or read

     * it is not among the last N committed versions
    """

    def __init__(self, writerTrx, page):
        """ 
        @param writerTrx: the transaction writing the page version
        @param page: the page to which this version belongs
        """
        self.writerTrx = writerTrx   # the transaction writing the page version
        self.readerTrxs = set()      # transactions reading this page version


if __name__ == "__main__":

#     def Trx(readPageOrdinal, writePageOrdinal):
#         with Transaction() as trx:
#             trx.readPage(pp[readPageOrdinal])
#             yield
#             trx.writePage(pp[writePageOrdinal])

    pp = PagePool(5)
    p0 = pp[0]
    t1 = Transaction()
    t2 = Transaction()
    t1.readPage(p0)
    t2.readPage(p0)
    t1.writePage(p0)
    t2.writePage(p0)
    t1.end()
    t2.end()
