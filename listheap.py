from enum import Enum
from math import inf
from timeit import default_repeat


ITERABLE_SINGLES = (str,)


def attrgetter(*args, default=()):
    if isinstance(default, ITERABLE_SINGLES):
        default = (default,) * len(args)
    try:
        default = tuple(default)
    except TypeError:
        default = (default,) * len(args)
    if default and len(args) != len(default):
        raise ValueError('invalid defaults')
    def get_attr(obj):
        if default:
            values = list(default)
            for ind, attr in enumerate(args):
                values[ind] = getattr(obj, attr, values[ind])
        else:
            values = [None] * len(args)
            for ind, attr in enumerate(args):
                values[ind] = getattr(obj, attr)
        return tuple(values)
    return get_attr


class HeapType(str, Enum):
    MIN = 'min'
    MAX = 'max'


class Node:
    def __init__(self, value=None):
        self.value = value
        self.last = self.next = None
    def __repr__(self):
        return '{}({})'.format(type(self).__name__, self.value)
    def __eq__(self, other):
        return self.value == other
    def __ne__(self, other):
        return self.value != other
    def __le__(self, other):
        return self.value <= other
    def __lt__(self, other):
        return self.value < other
    def __ge__(self, other):
        return self.value >= other
    def __gt__(self, other):
        return self.value > other
    def __hash__(self):
        return hash(self.value)
    def merge(self, other):
        self.next, other.last = other, self
        return self, other
    def get_offset(self, offset):
        node = self
        while node.next and offset > 0:
            node = node.next
            offset -= 1
        while node.last and offset < 0:
            node = node.last
            offset += 1
        return node
    def delete(self):
        outp = (self.last, self.next)
        if self.next:
            self.next.last = self.last
        if self.last:
            self.last.next = self.next
        self.last = self.next = None
        return outp


class HeapNode(Node):
    def __init__(self, value=None):
        super().__init__(value)
        self.left = self.right = self.parent = None
    def merge(self, other):        if self.parent:
            if self.parent.right:
                other.parent = self.parent.next
                other.parent.left = other
            else:
                other.parent = self.parent
                self.parent.right = other
        else:
            other.parent = self
            self.left = other
        return super().merge(other)
    def delete(self):
        if self.parent:
            if self is self.parent.left:
                self.parent.left = self.left or self.right
            elif self is self.parent.right:
                self.parent.right = self.right or self.left
        if self.left:
            self.left.parent = self.parent
        if self.right:
            self.right.parent = self.parent
        self.left = self.right = self.parent = None
        return super().delete()


class LinkedList:
    def __init__(self, iterable=()):
        if not hasattr(self, '_nodetype'):
            self._nodetype = Node
        self.head = self.tail = None
        self.len = 0
        if iterable:
            for value in iterable:
                self.appendright(value)
    @classmethod
    def _name(cls):
        return cls.__name__
    def __repr__(self):
        liststr = str(list(self)) if self.len else ''
        return '{}({})'.format(self._name(), liststr)
    def __len__(self):
        return self.len
    def __bool__(self):
        return self.len > 0
    def __getitem__(self, item):
        if isinstance(item, slice):
            start, stop, step = item.indices(self.len)
            if (stop-start) / step < 0:
                return []
            return [i.value for i in self._get_slice(item)]
        if isinstance(item, int):
            if abs(item) > self.len or item == self.len:
                raise IndexError('{} index out of range'.format(self._name()))
            if item < 0:
                return self.tail.get_offset(item+1)
            return self.head.get_offset(item)
        errstr = '{} indices must be integers or slices, not {}'
        raise TypeError(errstr.format(self._name(), type(item).__name__))
    def __delitem__(self, item):
        if isinstance(item, slice):
            for node in self._get_slice(item):
                if node is self.tail:
                    self.tail = self.tail.last
                if node is self.head:
                    self.head = self.head.next
                self.len -= 1
                node.delete()
        elif isinstance(item, int):
            if abs(item) > self.len or item == self.len:
                raise IndexError('{} index out of range'.format(self._name()))
            if item < 0:
                node = self.tail.get_offset(item+1)
            else:
                node = self.head.get_offset(item)
            if node is self.tail:
                self.tail = self.tail.last
            if node is self.head:
                self.head = self.head.next
            node.delete()
            self.len -= 1
        else:
            errstr = '{} indices must be integers or slices, not {}'
            raise TypeError(errstr.format(self._name(), type(item).__name__))
    def __setitem__(self, item, value):
        if isinstance(item, slice):
            if not hasattr(value, '__iter__'):
                raise TypeError('can only assign an iterable')
            nodes = self._get_slice(item)
            if (item.step or 1) != 1:
                if not nodes:
                    return
                values = list(value)
                if len(nodes) != len(values):
                    errstr = ('attempt to assign sequence of size {} to '
                              'extended slice of size {}')
                    raise ValueError(errstr.format(len(values), len(nodes)))
                for node, val in zip(nodes, values):
                    node.value = val
            else:
                values = type(self)(value)
                if not self.head:
                    self.merge(values)
                    return
                start, stop = item.indices(self.len)[:2]
                first = nodes[0]
                if start >= self.len:
                    self.tail.merge(values.head)
                    self.len += values.len
                elif stop < start:
                    if first.last:
                        first.last.merge(values.head)
                    else:
                        self.head = values.head
                    values.tail.merge(first)
                    self.len += values.len
                else:
                    last = nodes[-1]
                    self.len -= stop - start
                    self.len += values.len
                    if first.last:
                        first.last.merge(values.head)
                    else:
                        self.head = values.head
                    if last.next:
                        values.tail.merge(last.next)
                    else:
                        self.tail = values.tail
        elif isinstance(item, int):
            if abs(item) > self.len or item == self.len:
                msg = '{} assignment index out of range'.format(self._name())
                raise IndexError(msg)
            if item < 0:
                self.tail.get_offset(item+1).value = value
            else:
                self.head.get_offset(item).value = value
        else:
            errstr = '{} indices must be integers or slices, not {}'
            raise TypeError(errstr.format(self._name(), type(item).__name__))
    def __iter__(self):
        node = self.head
        while node:
            yield node.value
            node = node.next
    def __reversed__(self):
        node = self.tail
        while node:
            yield node.value
            node = node.last
    def __eq__(self, other):
        if hasattr(other, '__next__'):
            return False
        for i, j in zip(self, other):
            if i != j:
                return False
        return True
    def _get_slice(self, slice_):
        if not self.head:
            return []
        start, stop, step = slice_.indices(self.len)
        ind = start
        nodes = []
        if step > 0:
            node = self.head.get_offset(start)
        else:
            node = self.tail.get_offset(start-self.len+1)
        if not node:
            return []
        while node and (start <= ind < stop) or (start >= ind > stop):
            nodes.append(node)
            ind += step
            node = node.get_offset(step)
        return nodes
    def appendright(self, value):
        node = self._nodetype(value)
        if self.head:
            self.tail = self.tail.merge(node)[1]
        else:
            self.head = self.tail = node
        self.len += 1
    def appendleft(self, value):
        node = self._nodetype(value)
        if self.head:
            self.head = node.merge(self.head)[0]
        else:
            self.head = self.tail = node
        self.len += 1
    def copy(self):
        return type(self)(iter(self))
    def popleft(self):
        if not self.head:
            raise IndexError('pop from empty {}'.format(self._name()))
        outp = self.head.value
        self.head = self.head.delete()[1]
        self.len -= 1
        if self.len == 0:
            self.head = self.tail = None
        return outp
    def popright(self):
        if not self.head:
            raise IndexError('pop from empty {}'.format(self._name()))
        outp = self.tail.value
        self.tail = self.tail.delete()[0]
        self.len -= 1
        if self.len == 0:
            self.head = self.tail = None
        return outp
    def merge(self, other):
        if self.head:
            if other.head:
                self.tail.merge(other.head)
                self.tail = other.tail
                other.head = self.head
            else:
                other.head = self.head
                other.tail = self.tail
        else:
            self.head = other.head
            self.tail = other.tail
        self.len += other.len
        return self


class Queue(LinkedList):
    pop = LinkedList.popleft
    append = LinkedList.appendright


class Stack(LinkedList):
    pop = LinkedList.popright
    append = LinkedList.appendright


class Heap(LinkedList):
    def __init__(self, iterable=(), heaptype=HeapType.MIN):
        if heaptype not in set(HeapType):
            raise ValueError('invalid heap type: {}'.format(heaptype))
        self._nodetype = HeapNode
        super().__init__(iterable)
        self.type = heaptype
    def __repr__(self):
        nodes = list(self)
        liststr = '{}, '.format(nodes) if nodes else ''
        return '{}({}heaptype={})'.format(self._name(), liststr, repr(self.type))
    def __eq__(self, other):
        from collections import Counter
        if self[0] != other[0]:
            return False
        if self._type != getattr(other, 'type', self._type):
            return False
        return Counter(self) == Counter(other)
    def heapify(self):
        def buildparent():
            node.left = fast
            node.right = fast.next
            fast.parent = node
            fast.left = fast.right = None
            if fast.next:
                fast.next.parent = node
                fast.next.left = fast.next.right = None
        if self.len < 2:
            return
        node = self.head
        fast = node.next
        buildparent()
        while fast.next and fast.next.next:
            if node is fast or node is fast.next:
                raise AttributeError('circular lists cannot be heapified')
            node = node.next
            fast = fast.next.next
            buildparent()
        while node:
            self._siftdown(node)
            node = node.last
    def _siftdown(self, node):
        def swap(node1, node2):
            node1.value, node2.value = node2.value, node1.value
        if self._type == HeapType.MAX:
            func = max
            default = -inf
        else:
            func = min
            default = inf
        parent = func(node,
                      node.left,
                      node.right,
                      key=attrgetter('value', default=default))
        while parent is not node:
            swap(node, parent)
            node = parent
            parent = func(node,
                          node.left,
                          node.right,
                          key=attrgetter('value', default=default))
    def _siftup(self, node):
        def swap(node1, node2):
            node1.value, node2.value = node2.value, node1.value
        if self._type == HeapType.MAX:
            func = min
            default = inf
        else:
            func = max
            default = -inf
        child = func(node,
                     node.parent,
                     key=attrgetter('value', default=default))
        while child is not node:
            swap(node, child)
            node = child
            child = func(node,
                         node.parent,
                         key=attrgetter('value', default=default))
    @property
    def type(self):
        return self._type
    @type.setter
    def type(self, heaptype, re_heapify=True):
        if heaptype not in set(HeapType):
            raise ValueError('invalid heap type: {}'.format(heaptype))
        if hasattr(self, '_type'):
            heaptype, self._type = self._type, heaptype
            if heaptype != self._type and re_heapify:
                self.heapify()
        else:
            self._type = heaptype
            if re_heapify:
                self.heapify()
    def append(self, value):
        self.appendright(value)
        self._siftup(self.tail)
    def pop(self):
        if not self.head:
            raise IndexError('pop from empty {}'.format(self._name()))
        outp, self.head.value = self.head.value, self.tail.value
        self.tail = self.tail.delete()[0]
        self._siftdown(self.head)
        self.len -= 1
        if self.len == 0:
            self.head = self.tail = None
        return outp
    def copy(self):
        return type(self)(iter(self), heaptype=self._type)
    def merge(self, other):
        if type(self.head) is type(other.head):
            type(other).type.fset(other, self.type, False)
            super().merge(other)
            self.heapify()
        else:
            super().merge(type(self)(other))
            self.heapify()
        return self


def unit_test(size=10):
    from heapq import heapify
    class RevInt(int):
        def __lt__(self, other):
            return super().__gt__(other)
        def __gt__(self, other):
            return super().__lt__(other)
        def __le__(self, other):
            return super().__ge__(other)
        def __ge__(self, other):
            return super().__le__(other)
    def test_list(cls, pop=False, pop_forward=True):
        from collections import deque
        lst = cls()
        base = []
        def build():
            nonlocal lst, base
            base = list(range(size))
            lst = cls(base)
        build()
        empty = cls()
        assert lst == base
        assert lst
        assert not empty
        assert len(lst) == len(base)
        assert list(lst) == base
        assert list(reversed(lst)) == list(reversed(base))
        assert lst.copy() == lst
        assert lst[mid] == base[mid]
        assert lst[:mid] == base[:mid]
        assert lst[mid:] == base[mid:]
        assert lst[low_mid:hi_mid] == base[low_mid:hi_mid]
        assert lst[:hi_hi] == base
        assert lst[-1] == base[-1]
        assert lst[low_mid:hi_mid:2] == base[low_mid:hi_mid:2]
        assert lst[hi_mid:low_mid] == []
        assert lst[hi_mid:low_mid:-1] == base[hi_mid:low_mid:-1]
        assert lst[low_low:low_mid:-1] == base[low_low:low_mid:-1]
        assert lst.copy() == lst
        lst[mid] = base[mid] = low
        assert lst == base
        lst[mid] = base[mid] = mid
        lst[:low_mid] = base[:low_mid] = insert
        assert lst == base
        build()
        lst[hi_mid:] = base[hi_mid:] = insert
        assert lst == base
        build()
        lst[low_mid:hi_mid] = base[low_mid:hi_mid] = insert
        assert lst == base
        build()
        lst[mid:hi_hi] = base[mid:] = insert
        assert lst == base
        build()
        lst[low_mid:hi_mid:2] = base[low_mid:hi_mid:2] = insert[:mid:2]
        assert lst == base
        build()
        lst[hi_mid:low_mid:-1] = base[hi_mid:low_mid:-1] = insert[:mid]
        assert lst == base
        build()
        del lst[mid], base[mid]
        assert lst == base
        build()
        del lst[mid:], base[mid:]
        assert lst == base
        build()
        del lst[:mid], base[:mid]
        assert lst == base
        build()
        del lst[low_mid:hi_mid], base[low_mid:hi_mid]
        assert lst == base
        build()
        del lst[low_mid:hi_mid:2], base[low_mid:hi_mid:2]
        assert lst == base
        build()
        del lst[hi_mid:low_mid:-1], base[hi_mid:low_mid:-1]
        assert lst == base
        build()
        lst.merge(cls())
        assert lst == base
        empty.merge(lst)
        assert empty == base
        lst.merge(cls(base))
        base += base
        assert lst == base
        build()
        que = deque(base)
        assert lst.popleft() == que.popleft()
        assert lst == que
        assert lst.popright() == que.pop()
        assert lst == que
        que.append(hi)
        lst.appendright(hi)
        assert lst == que
        que.appendleft(low)
        lst.appendleft(low)
        assert lst == que
        if pop:
            lst.append(size)
            que.append(size)
            assert lst == que
            if pop_forward:
                assert lst.pop() == que.pop()
                assert lst == que
            else:
                assert lst.pop() == que.popleft()
                assert lst == que
    low = 0
    hi = size - 1
    mid = hi // 2
    low_mid = mid // 2
    hi_mid = low_mid + mid
    low_low = low - low_mid
    hi_hi = hi + low_mid
    insert = list(range(hi_mid))

    test_list(LinkedList)
    test_list(Stack, pop=True)
    test_list(Queue, pop=True, pop_forward=False)
    test_list(Heap)

    fwd_list = list(range(size))
    fwd_heap = list(reversed(range(size)))
    heapify(fwd_heap)
    rev_heap = [RevInt(i) for i in range(size)]
    heapify(rev_heap)
    min_heap = Heap(reversed(fwd_list))
    max_heap = Heap(heaptype=HeapType.MAX)
    assert repr(LinkedList(fwd_list)) == 'LinkedList({})'.format(fwd_list)
    assert repr(LinkedList()) == 'LinkedList()'
    assert repr(Queue()) == 'Queue()'
    assert repr(Stack(fwd_list)) == 'Stack({})'.format(fwd_list)
    assert repr(min_heap) == 'Heap({}, heaptype={})'.format(fwd_heap,
                                                            repr(HeapType.MIN))
    assert repr(max_heap) == 'Heap(heaptype={})'.format(repr(HeapType.MAX))

    assert min_heap.copy() == min_heap
    max_heap.merge(Stack(fwd_list))
    assert list(max_heap) == rev_heap
    assert type(max_heap.head) is HeapNode
    assert max_heap != min_heap
    min_heap.type = HeapType.MAX
    assert max_heap == min_heap
    min_heap.type = HeapType.MIN
    for low, hi in zip(fwd_list, reversed(fwd_list)):
        assert min_heap.pop() == low
        assert max_heap.pop() == hi
    for low, hi in zip(fwd_list, reversed(fwd_list)):
        min_heap.append(hi)
        max_heap.append(low)
        assert min_heap.head.value == hi
        assert max_heap.head.value == low
    total_heap = list(min_heap) + list(max_heap)
    heapify(total_heap)
    min_heap.merge(max_heap)
    assert min_heap.type == max_heap.type
    assert min_heap.head is max_heap.head
    assert min_heap.tail is max_heap.tail
    assert list(min_heap) == total_heap
