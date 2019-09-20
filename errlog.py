"""Better exception logging"""
from functools import wraps

def print_exc(exc=None):
    """Print an exception (print('\\n'.join(format_exc(exc))))"""
    print('\n'.join(format_exc(exc)))
#

@wraps(print_exc)
def print_exception(*args, **kwargs):
    """alias for print_exc"""
    print_exc(*args, **kwargs)

def format_exc(exc=None):
    """Format an exception to be printed"""
    from sys import exc_info
    from traceback import TracebackException
    from itertools import chain
    if exc is None:
        exc = exc_info()
    tbe = TracebackException(*exc, limit=None, capture_locals=True)
    itr = chain.from_iterable(lin.split('\n') for lin in tbe.format(chain=None))
    title = (next(itr), '  Globals:') # pylint: disable=R1708
    globals_ = exc[2].tb_frame.f_globals
    globals_ = ('    {} = {}'.format(k, v) for k, v in globals_.items())
    yield from chain(title, globals_, (i for i in itr if i != ''))
#

@wraps(format_exc)
def format_exception(*args, **kwargs):
    """alias for format_exc"""
    format_exc(*args, **kwargs)

def _test():
    default_tb()
    custom_tb()
#
def tst(seq):
    """Test function which may error"""
    out = []
    for i in seq:
        out.append('0' * (4 - len(i)) + i)
    #
    return out
#
def print_header_wrapper(disp, siz=120):
    """Wrapper function to print a header and footer"""
    def wrapper(func):
        @wraps(func)
        def print_header(*args, **kwargs):
            print('-'*siz)
            print(disp)
            print('-'*siz)
            func(*args, **kwargs)
            print('-'*siz)
            print('')
        return print_header
    return wrapper
#
DATA = ['1', '2', 3, '4']
@print_header_wrapper('Default traceback exception:')
def default_tb():
    """Function to error and print the default traceback"""
    import traceback
    try:
        tst(DATA)
    except: # pylint: disable=W0702
        traceback.print_exc()
#
@print_header_wrapper('Custom exception:')
def custom_tb():
    """Function to error and print the custom traceback"""
    try:
        tst(DATA)
    except: # pylint: disable=W0702
        print_exc()
#

if __name__ == '__main__':
    _test()
