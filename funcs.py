"""Simply a library of random useful functions."""
from __future__ import generator_stop

def group_count(iterable):
    """Return the groups and their counts from an iterable."""
    from itertools import groupby
    yield from ((grp, len(list(items))) for grp, items in groupby(iterable))

def grouped(iterable, num=2, *, fill_all=False, fill=False, fillvalue=None):
    """Group an iterable into pairs (or groups of n length).

    For example, list(grouped(range(20),3)) == [(0, 1, 2), (3, 4, 5), (6, 7, 8),
    (9, 10, 11), (12, 13, 14), (15, 16, 17)]

    Pass the all flag to include the partial un-full group at the end, if one
    exists.
    Pass the fill flag with an optional fill value to fill the partial group at
    the end, if there is one, with the provided fill value (or none if no fill
    value was provided).
    """
    iterator = iter(iterable)  #Turn the iterable into an iterator
    if fill:  #If filling missing values
        #Import zip_longest to fill in missing values
        from itertools import zip_longest
        #Create N copies of the iterator, then zip them together, filling
        #missing values with the fill value
        return zip_longest(*[iterator]*num, fillvalue=fillvalue)
    #
    if fill_all:  #If returning all elements
        def gen():  #Create a generator function, for similar functionality
            from itertools import islice  #For slicing iterator objects
            #Take the first n items and convert to a tuple
            out = tuple(islice(iterator, num))
            while out:  #While the next tuple is not empty
                yield out  #Yield the next tuple
                #Take the next n items and convert to a tuple
                out = tuple(islice(iterator, num))
            #
        #
        return gen()  #Return the generator function
    #
    #If not filling and not returning all elements, create N copies of the
    #iterator and zip them, stopping at the shortest one
    return zip(*[iterator]*num)
#

#Iterate through each element of an iterator in groups
def groupwise(iterable, num=2):
    """Iterate through in iterator in pairs (or groups of n length).

    For example, list(groupwise(range(10),3)) == [(0, 1, 2), (1, 2, 3),
    (2, 3, 4), (3, 4, 5), (4, 5, 6), (5, 6, 7), (6, 7, 8), (7, 8, 9)]
    """
    #Import tee to copy iterators, count for a quick counter, and islice for
    #consuming items from an iterator
    from itertools import count, islice, tee
    #Turn the iterable into an iterator and create n copies of the iterator
    iters = tee(iter(iterable), num)
    #Iterate through the copies of the iterator
    for i, iterator in zip(count(), iters):
        #Advance to an empty slice at the ith element, consuming the first i
        #elements
        next(islice(iterator, i, i), None)
    #
    #Zip the iterators together and return the zipped iterators
    return zip(*iters)
#


def base_converter(num_expr, base, num_decimals=12):
    """Converts input expression to the provided base.
    
    To convert digits to decimal values from the provided base, use the
    following dictionary:
        {str(i) if i < 10 else chr(55+i):i for i in range(36)}
    
    Args:
        num_expr: The number or numeric string to be converted to another base
        base: The base to which to convert (valid values are 2 to 36 inclusive)
        num_decimals: The maximum number of digits after the decimal place
    
    Returns:
        A string representation of the provided numeric expression in the
        provided base.
    
    Raises:
        ValueError: The base argument is outside the bounds of 2 to 36 inclusive
    """
    from collections import deque
    from fractions import Fraction
    if base > 36:
        raise ValueError('cannot represent all digits in bases > 36!')
    if base < 2:
        raise ValueError('cannot convert to bases < 2!')
    #Build dictionaries for easy lookup.
    digits = {i:str(i) if i < 10 else chr(55+i) for i in range(36)}
    numbers = {str(i) if i < 10 else chr(55+i):i for i in range(36)}
    #Use fractions to avoid floating point errors.
    num = Fraction(num_expr)
    pow = Fraction(base, 1)
    outp = []
    #Track number of decimal places to prevent running forever.  With the
    #addition of repeated digit tracking, this is more for space conditions than
    #for runtime, but it will keep in check things like pi or e.
    decimals = -1
    #Create a dictionary of ratios seen.  If we see a ratio in relation to the
    #base that we've seen before, we're going to start repeating digits.  For
    #example, 1/3 in base 4 is 1/3 of 1.  When you subtract 1/4, you get 1/12...
    #which is 1/3 of 1/4.  By checking the ratios, we know that the sequence of
    #digits since the last time this ratio was seen (in this case, '1') will
    #repeat infinitely (because if we keep going, we'll eventually get to the
    #same ratio again).
    seen = {}
    #First, find the size of the largest digit by looking for the lowest power
    #of base which is greater than the input.
    while num >= pow:
        pow *= base
    #Drop down by one to get the largest digit
    pow /= base
    #While we're non-fractional, it's pretty easy.  Move down by on digit each
    #loop, decrementing the input and appending the appropriate digit to the
    #output.
    while pow >= 1 or (num and decimals < num_decimals):
        dig = num // pow
        num -= dig * pow
        ratio = Fraction(num.numerator,
                         Fraction(num.denominator, pow.denominator))
        outp.append(digits[dig])
        #If a repeating digit is found, strip all the digits since the last time
        #this ratio was seen and put them in parens.
        if ratio in seen:
            outp[seen[ratio]:] = ['({})...'.format(''.join(outp[seen[ratio]:]))]
            break
        #If power > 1, nothing special happens.  But if there's a fractional
        #part and power <= 1, insert the '.' and start building the seen
        #dictionary.  While computing the fractional part, track number of 
        #decimal places and update the dictionary of seen ratios.
        if num and pow == 1:
            outp.append('.')
        elif pow <= 1:
            seen[ratio] = len(outp)
            decimals += 1
        pow /= base
    else:
        #If we didn't break due to repeating digits, round up and indicate
        #that rounding occurred, if appropriate.
        if num // pow > 4:
            i = -1
            while numbers[outp[i]]+1 >= base:
                outp[i] = digits[(numbers[outp[i]]+1) % base]
                i -= 1
                if outp[i] == '.':
                    i -= 1
                if i <= -len(outp):
                    outp[0] = str(base)
                    break
            else:
                outp[i] = digits[numbers[outp[i]]+1]
        if num:
            outp.append('...')
    return ''.join(outp)
#


def kmp_prefix(inp, bound=None):
    """Return the KMP prefix table for a provided string."""
    #If no bound was provided, default to length of the input minus 1
    if not bound:
        bound = len(inp) - 1
    table = [0] * (bound+1)  #Initialize a table of length bound + 1
    ref = 0  #Start referencing at the beginning of the input
    #The first character doesn't need to be checked - start with the second
    chk = 1
    while chk < bound:  #While the check lies within the specified bounds
        #If the check character matches the reference character, a failed match
        #on the next character can start checking on the character after the
        #reference character (because it's necessarily already matched the
        #reference character)
        if inp[chk] == inp[ref]:
            chk += 1  #Increment the check and the reference
            ref += 1
            #After incrementing (so that the next set is logged), log the
            #reference character as the maximum prefix for the check character
            table[chk] = ref
        #If the characters don't match and we're not referencing the first
        #character in the input
        elif ref:
            #Drop the reference back to the maximum prefix for said reference to
            #continue checking there
            ref = table[ref]
        #If there's no match and we're at the beginning of the input, just
        #increment the check character
        else:
            chk += 1
        #
    #
    return table  #Return the prefix table
#


def kmp(term, space, table=None):
    """Return boolean indicating whether search term found within search space.

    This can be used for any iterator, and is essentially performing a substring
    search in a c-style string.
    A prefix table can be provided but is not necessary.
    """
    #Convert the inputs into lists so they can be indexed into (in case they're
    #iterable but not indexable)
    term = list(term)
    space = list(space)
    #Compute the lengths of the inputs to minimize the overhead from bunches of
    #calls to len
    termlen = len(term)
    spacelen = len(space)
    #If the search term can't fit within the search space, there's no need to
    #even check - it's not in there
    if termlen > spacelen:
        return False
    #
    if termlen < 1:  #All strings contain a null string
        return True
    #
    if not table:  #If no prefix table was provided, compute one
        table = kmp_prefix(term, termlen-1)
    #
    trg = ref = 0  #Start indexing at 0
    while trg < spacelen:  #While the target is within the search space
        #If the target character matches the reference character
        if space[trg] == term[ref]:
            trg += 1  #Increment both the taget and the reference
            ref += 1
            #If the reference was the last character in the search term, a match
            #was found
            if ref == termlen:
                return True
            #
            #Maybe if search term is expected to be really long, abort when
            #remaining length in search space is smaller than remaining length
            #in search term
        #If the characters don't match and we're not referencing the first
        #character in the search term
        elif ref:
            ref = table[ref]  #Drop the reference back based on the prefix table
        #If there's no match and the reference is at the beginning of the search
        #term
        else:
            trg += 1  #Increment the target
        #
    #
    #If we exited the loop by indexing out of the search space, no match was
    #found
    return False
#


class AhoTrie:
    """docstring"""
    class Node:
        """docstring"""
        def __init__(self, state, key,
                     childrenword=(None, ''), fail=None):
            """docstring"""
            children, word = childrenword
            self.state = state
            self.key = key
            self.fail = fail
            #Define children and words as empty and then override them because
            #if they're defined as empty structures in the default arguments,
            #then all instances of the class will use the same mutable object
            #rather than each instance having it's own
            self.children = {}
            self.words = []
            self.word = word
            if children:
                self.children = children

        def __repr__(self):
            """docstring"""
            return ('AhoTrie.Node({}, {}, '
                    'childrenword=({}, {}), fail={})').format(
                        repr(self.state), repr(self.key),
                        repr(self.children), repr(self.word),
                        repr(getattr(self.fail, 'key', None)))

        def __str__(self):
            """docstring"""
            return '{}({}->{}) {}'.format(self.key, self.state,
                                          getattr(self.fail, 'state', ''),
                                          self.word)

        def search(self, char):
            """docstring"""
            return self.children[char]

        def contains(self, char):
            """docstring"""
            return char in self.children

        def add_child(self, state, key):
            """docstring"""
            if key not in self.children:
                self.children[key] = AhoTrie.Node(state, key)
            return self.children[key]

        def build_str(self,
                      chars=('\u251c', '\u2514', '\u2502', '\u2500', '\u23ce'),
                      pref=''):
            """docstring"""
            #Builds a visual string to represent the tree, for printing
            def add_child(inp, char, out, next_pref):
                out.append('{}{}{} {}'.format(
                    pref, char, horz,
                    str(inp).replace('\n',
                                     '{}\n{}'.format(newl, next_pref))))
                out.extend(inp.build_str(chars=chars, pref=next_pref)[1:])
            fork, last, vert, horz, newl = chars
            out = [str(self)]
            children = list(self.children.values())
            for child in children[:-1]:
                add_child(child, fork, out, '{}{}  '.format(pref, vert))
            if children:
                add_child(children[-1], last, out, '{}   '.format(pref))
            return out

        def disp(self, asc=False):
            """docstring"""
            print(self.to_text(asc))

        def to_text(self, asc=False):
            """docstring"""
            if asc:
                return '\n'.join(self.build_str(('|', '+', '|', '-', '\\n')))
            return '\n'.join(self.build_str())

    class Root:
        """docstring"""
        def __init__(self):
            """docstring"""
            self.key = ''
            self.state = -1
            self.child = AhoTrie.Node(0, 'root', fail=self)
            self.words = []

        def __repr__(self):
            """docstring"""
            return 'AhoTrie.Root()'

        def __str__(self):
            """docstring"""
            return str(self.key)

        def contains(self, char):
            """docstring"""
            #These next two lines are unnecessary, but pylint complains if I
            #don't have them.  It doesn't like that I don't use the parameters
            #and it complains that it doesn't need to be a method.  But I need
            #it as a method and I need to take the parameter so that I can use
            #this in place of a Node object
            if char == self.key:
                return True
            return True

        def search(self, char):
            """docstring"""
            #These next two lines are unnecessary, but pylint complains if I
            #don't have them.  It doesn't like that I don't use the parameters
            #and it complains that it doesn't need to be a method.  But I need
            #it as a method and I need to take the parameter so that I can use
            #this in place of a Node object
            if char == self.key:
                return self.child
            return self.child

    def __init__(self, *terms):
        """docstring"""
        from itertools import count
        #Root node of the Trie is a child of a Root.  This is so that nodes can
        #fail back to the Root and get redirected to the root node of the Trie
        #without having to have a special case
        self.root = AhoTrie.Root().child
        self.counter = count()
        self.terms = terms
        self._dirty = True
        for word in terms:
            self.add_word(word)
        self._build_fail_tree()

    def __repr__(self):
        """docstring"""
        return 'AhoTrie({})'.format(','.join(repr(i) for i in self.terms))

    def __str__(self):
        """docstring"""
        return self.root.to_text()

    def add_word(self, word):
        """docstring"""
        #If the tree isn't dirty, it should be.  Wipe out the fail tree so it
        #can be re-built from scratch later
        if not self._dirty:
            self._clear_fail_tree()
        node = self.root
        for char in word:
            #If the prefix already exists, don't bother creating it
            if node.contains(char):
                node = node.search(char)
            else:
                node = node.add_child(next(self.counter), char)
        node.word = word
        node.words = [word]

    def _build_fail_tree(self):
        """docstring"""
        from collections import deque
        #Build the failure tree using a breadth-first search
        que = deque()
        que.append(self.root)
        while que:
            node = que.popleft()
            for char, child in node.children.items():
                #To find the failure node for the child, perform a forward
                #search for the child from the failure point of the parent
                nxt = node.fail
                while not nxt.contains(char):
                    nxt = nxt.fail
                child.fail = nxt.search(char)
                #For output purposes, concatenate the word list of the child
                #with that of it's failure point
                if child.fail.words:
                    child.words.extend(child.fail.words)
                que.append(child)
        self._dirty = False

    def _clear_fail_tree(self):
        """docstring"""
        from collections import deque
        #Wipe out the failure tree using a breadth-first search
        que = deque()
        que.append(self.root)
        while que:
            node = que.popleft()
            for child in node.children.values():
                #No need to check anything - just revert the fail point and word
                #list to default
                child.fail = None
                child.words = []
                if child.word:
                    child.words = [child.word]
                que.append(child)
        self._dirty = True

    def disp(self):
        """docstring"""
        self.root.disp()

    def search(self, space):
        """docstring"""
        #If the tree is dirty, we need to build the failure tree
        if self._dirty:
            self._build_fail_tree()
        node = self.root
        for pos, char in enumerate(space):
            while not node.contains(char):
                node = node.fail
            node = node.search(char)
            for word in node.words:
                yield word, pos
        #This could pretty easily be modified to include start point of the
        #match - for efficiency, though, we'd grab the length of the word when
        #adding it to the tree and store the length of the word with the word
        #itself, so we don't need to find the length but once in ever.
#


def bitmap(num, ind=0):
    """docstring"""
    bits = []
    bit = ind
    while num:
        if num & 1:
            bits.append(bit)
        #
        num >>= 1
        bit += 1
    #
    return bits
#
def get_lsb(num):
    """docstring"""
    return num & -num
#
def get_lsb_num(num):
    """docstring"""
    cnt = 0
    while not (num>>cnt) & 1:
        cnt += 1
    #
    return cnt + 1
#
def get_msb(num):
    """docstring"""
    while num & (num-1):
        num &= num - 1
    #
    return num
#
def get_msb_num(num):
    """docstring"""
    cnt = 0
    while num >> cnt:
        cnt += 1
    #
    return cnt
#
def sub_bit(num, bit=None):
    """docstring"""
    if bit is None:
        bit = get_lsb(num)
    #
    #Can return num - bit, but bitwise operations tend to be faster
    return num ^ bit
#
def add_bit(num, bit=None):
    """docstring"""
    if bit is None:
        bit = get_lsb(num)
    #
    #If there's no ALU, you need to do some fancy stuff - invert LSB, or with
    #original number, get LS0B, invert LS0B, XOR LS0B with inverted LS0B with
    #original number.  With an ALU, this is 6 or so cycles slower, but without
    #it's at least constant time
    return num + bit
#

class Trie:
    """docstring"""
    class Node:
        """docstring"""
        def __init__(self, key, children=None):
            """docstring"""
            self.key = key
            self.word = False
            self.children = {}
            if children:
                self.children = children

        def __eq__(self, other):
            """docstring"""
            return self.key == other.key and self.children == other.children

        def __ne__(self, other):
            """docstring"""
            return self.key != other.key or self.children != other.children

        def __repr__(self):
            """docstring"""
            return 'Trie.Node(key={}, children={})'.format(repr(self.key),
                                                           repr(self.children))

        def disp(self, prnt=True):
            """docstring"""
            if prnt:
                start = 'letters={'
            else:
                start = 'children={'
            if self.children:
                lines = [start]
                for k, val in self.children.items():
                    k = repr(k)
                    child_lines = iter(val.disp(False))
                    lines.append('{:{len}}{}: {}'.format('',
                                                         k,
                                                         next(child_lines),
                                                         len=len(start)))
                    lines.extend(['{:{len}}{}'.format('',
                                                      i,
                                                      len=2+len(k)+len(start))
                                  for i in child_lines])
                    if val.children:
                        lines[-1] = lines[-1][2+len(k):]
                    lines[-1] += ','
                lines[-1] = lines[-1][:-1]
                lines.append('}')
            else:
                lines = [start+'}']
            if prnt:
                print('\n'.join(lines))
                return None
            return lines

    def __init__(self, words=None, root=None):
        """docstring"""
        if not words:
            words = []
        if not root:
            self.root = self.Node('')
        else:
            self.root = root
        for word in words:
            self.add_word(word)

    def __eq__(self, other):
        """docstring"""
        return self.root == other.root and self.get_words() == other.get_words()

    def __ne__(self, other):
        """docstring"""
        return self.root != other.root or self.get_words() != other.get_words()

    def __repr__(self):
        """docstring"""
        return 'Trie(words={}, root={})'.format(repr(self.get_words()),
                                                repr(self.root))

    def add_word(self, word):
        """docstring"""
        node = self.root
        for char in word:
            if char in node.children:
                node = node.children[char]
            else:
                new_node = self.Node(char)
                node.children[char] = new_node
                node = new_node
        node.word = True

    def get_words(self, node=None):
        """docstring"""
        if node is None:
            node = self.root
        out = []
        if node.word:
            out.append('')
        for child in node.children.values():
            out.extend('{}{}'.format(child.key, i)
                       for i in self.get_words(child))
        return out

    def remove_word(self, word):
        """docstring"""
        word_nodes = [node] = [self.root]
        for char in word:
            if char not in node.children:
                return
            node = node.children[char]
            word_nodes.append(node)
        node.word = False
        for char, node in reversed(list(zip(word, word_nodes))):
            if node.children[char].word or node.children[char].children:
                return
            del node.children[char]

    def search_word(self, word):
        """docstring"""
        node = self.root
        for char in word:
            if char in node.children:
                node = node.children[char]
            else:
                return False
        return node.word

    def search_prefix(self, prefix):
        """docstring"""
        node = self.root
        for char in prefix:
            if char in node.children:
                node = node.children[char]
            else:
                return False
        return True

    def show_tree(self):
        """docstring"""
        self.root.disp()
#

def merge_sort(inp, left=0, rght=None, flex=None):
    """docstring"""
    if rght is None:
        rght = len(inp)
    if (rght-left) <= 1:
        return inp
    mid = (rght-left) // 2
    if flex is None:
        flex = [0] * mid
    lend = left + mid
    merge_sort(inp, left=left, rght=lend, flex=flex)
    merge_sort(inp, left=lend, rght=rght, flex=flex)
    flex[:mid] = inp[left:left+mid]
    j = lend
    k = left
    for i in range(mid):
        while j < rght and inp[j] < flex[i]:
            inp[k] = inp[j]
            j += 1
            k += 1
        inp[k] = flex[i]
        flex[i] = 0
        k += 1
    return inp
#

def merge_sort_sp(inp, length=None, offs=0):
    """docstring"""
    if length is None:
        length = len(inp)
    if (length-offs) <= 1:
        return inp
    mid = length // 2
    lend = offs + mid
    lft = inp[offs:lend]
    merge_sort_sp(lft, length=mid)
    merge_sort_sp(inp, length=length, offs=lend)
    j = lend
    k = offs
    for i in range(mid):
        while j < length and inp[j] < lft[i]:
            inp[k] = inp[j]
            j += 1
            k += 1
        inp[k] = lft[i]
        k += 1
    return inp
#

def merge_sort_p(inp):
    """docstring"""
    if len(inp) <= 1:
        return inp
    mid = len(inp) // 2
    rlen = len(inp) - mid
    lft = merge_sort_p(inp[:mid])
    rgt = merge_sort_p(inp[mid:])
    i = j = 0
    out = []
    while i < mid or j < rlen:
        if j >= rlen or (i < mid and lft[i] <= rgt[j]):
            out.append(lft[i])
            i += 1
        else:
            out.append(rgt[j])
            j += 1
    return out
#

from functools import wraps

class ClassPropertyMetaclass(type):
    _class_property = ['value']
    _instance_readable_class_property = 'VALUE'
    _instance_readwritable_class_property = 'value'

    @wraps(type.__init__)
    def __init__(cls, *args, **kwargs):
        super().__init__(*args, **kwargs)

    @property
    def class_property(cls):
        return cls._class_property

    @class_property.setter
    def class_property(cls, input):
        if input:
            cls._class_property.append(input)
        else:
            cls._class_property.append(input)

    @property
    def instance_readwritable_class_property(cls):
        return cls._instance_readwritable_class_property

    @instance_readwritable_class_property.setter
    def instance_readwritable_class_property(cls, input):
        if input:
            cls._instance_readwritable_class_property = input
        else:
            cls._instance_readwritable_class_property = input

    @property
    def instance_readable_class_property(cls):
        return cls._instance_readable_class_property

    @instance_readable_class_property.setter
    def instance_readable_class_property(cls, input):
        if input:
            cls._instance_readable_class_property = input
        else:
            cls._instance_readable_class_property = input


class ClassProperty(metaclass=ClassPropertyMetaclass):
    @property
    def instance_readwritable_class_property(self):
        return type(self).instance_readwritable_class_property

    @instance_readwritable_class_property.setter
    def instance_readwritable_class_property(self, input):
        if input:
            type(self).instance_readwritable_class_property = input
        else:
            type(self).instance_readwritable_class_property = input

    @property
    def instance_readable_class_property(self):
        return type(self).instance_readable_class_property


class InstanceTrackingClassMeta(type):
    @wraps(type.__init__)
    def __init__(cls, *args, **kwargs):
        from weakref import WeakValueDictionary
        super().__init__(*args, **kwargs)
        cls._instances = WeakValueDictionary()

    @property
    def instances(cls):
        return list(cls._instances.values())


class InstanceTrackingClass(metaclass=InstanceTrackingClassMeta):
    def __new__(cls, *args, **kwargs):
        new = super().__new__(cls)
        cls._instances[id(new)] = new
        return new


if __name__ != '__main__':
    #If importing
    from random import shuffle
    LST = list(range(9000))
    shuffle(LST)
