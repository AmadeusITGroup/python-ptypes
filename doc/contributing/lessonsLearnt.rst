==========================================
Lessons learnt while developing ``ptypes``
==========================================

This document is intended at developers who want to participate in evolving
``ptypes``. It contains lessons learnt the hard way and explains why some of the 
things are like they are.

Every .pyx module has to be compiled into a dedicated extension module
----------------------------------------------------------------------
2014-11-04

That is, in setup.py a separate extension object has to be created for it.
Although one can compile multiple pyx files into a single extension::

           Extension(modname, 
                     ["ptypes/__init__.pyx",
                      "ptypes/basetypes.pyx",
                      "ptypes/pallocator.pyx",
                      "ptypes/graph.pyx",
                      "ptypes/md5.c",
                      ], 
                     include_dirs=['.']
                     )

the resulting extension module cannot be imported. The reason is that the module initialization functions are inserted only
into the c files matching the name of the extension module (i.e. modname). If there is no such c file, we get 
"ImportError: init function missing". Even if there is one such file, the types defined in the other will not 
get registered. Even if we could get setup.py compile it into an importable module, 
the pyximport utility would not be usable with the module (although there is a slight chance we could hack it to work).
 
The alternative is rename the pyx files not matching the name of the extension module to \*.pxi and include them into the 
matching one. However this would be little benefit over having everything in the same file. 
The lack of modularity would lead to high compilation times, concerns would not be separated, 
testing and extendability not promoted. So we go for one extension mod per pyx. 

This decision may raise concerns about the compiler not being able to optimize as heavily as with the monolithic solution, 
but we will overcome this by inline-ing the functions suspected to be too hot.

References:
...........
* http://stackoverflow.com/questions/8024805/cython-compiled-c-extension-importerror-dynamic-module-does-not-define-init-fu
* http://stackoverflow.com/questions/11698482/project-structure-for-wrapping-many-c-classes-in-cython-to-a-single-shared-obj
* http://stackoverflow.com/questions/8772966/how-can-i-merge-multiple-cython-pyx-files-into-a-single-linked-library
* http://osdir.com/ml/python-cython-devel/2009-10/msg00339.html

How should persistent types be declared?
----------------------------------------
2014-11-06

They will have to be declared in a call-back function: the pallocator knows when to call it and if at all.
If we leave this decision to the developer, it will be error-prone.

There are various alternatives for the syntax. For example::

    def createTypes(pallocator):
    
        # register all non-parametric types found in a module
        pallocator.register(basetypes)
        
        # register a single non-parametric type under its default name  
        pallocator.register(Int)
        
        # alternative syntax:
        Int.typedef(pallocator)
        
        
        # register a single non-parametric type under another name  
        pallocator.register(Int('uint'))
        
        # alternative syntax:
        Int.typedef(pallocator, 'uint')
        
        # class syntax:
        class uint(pallocator, Int): pass
        
        
        # register a parametric type under a name (here the name is mandatory)  
        pallocator.register(Dict('floatbyuint')[uint, float])
        
        # alternative syntax:
        Dict.typedef(pallocator, 'floatbyuint', uint, float)
        
        # class syntax:
        class floatbyuint(pallocator, Dict[uint, float]): 
         pass
    
 The advantage of the class syntax is that it immediately introduces the name of the type in the local name space.
 
Can we avoid __metaclass__ in Structure definitions?
----------------------------------------------------

 2014-11-12

 If ``__metaclass__ = StructureMeta`` is placed inside Structure, ``Structure``
 will be made a
 ``StructureMeta`` as opposed to using the ``cdef class Structure``.
 I also tried to assign ``Structure.__metaclass__ = StructureMeta``, 
 but this raises an exception.
 Tried to define a subclass of ``Structure`` with 
 ``__metaclass__ = StructureMeta``. This gave no errors
 (had to patch ``StructureMeta.__init__`` so it does not initialize this class ) 
 but neither had any effect when further deriving from that class in 
 ``populateSchema()``. 