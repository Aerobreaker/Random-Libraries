print('\n'.join('{:0>{}} - {:<{}} ({})'.format(i, len(str(len(object.__subclasses__()))), j.__name__, len(max((k.__name__ for k in object.__subclasses__()), key=len)), j) for i, j in enumerate(object.__subclasses__())))




>>> exec('__import__("os").system("bad.bat")')

Python>echo/This is a batch file that does bad stuff
This is a batch file that does bad stuff
>>> exec('__import__("os").system("bad.bat")', {'__globals__':{}})

Python>echo/This is a batch file that does bad stuff
This is a batch file that does bad stuff
>>> exec('__import__("os").system("bad.bat")', {'__builtins__':{}})
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "<string>", line 1, in <module>
NameError: name '__import__' is not defined
>>> exec('[i for i in ().__class__.__bases__[0].__subclasses__() if i.__name__ == "BuiltinImporter"][0].load_module("os").system("bad.bat")', {'__builtins__':{}})

Python>echo/This is a batch file that does bad stuff
This is a batch file that does bad stuff





exec("[print('\\n{}\\n'.format('\\n'.join(*(['Duplicate found!\\n{}'.format(id) for (id, cnt) in __import__('collections').Counter(tuple(__import__('itertools').compress(line.strip().split(','), cols)) for cols, line in zip(__import__('itertools').repeat([[1 if i+1 in set(s) else 0 for i in range(max(s))] for s in [[int(i) for i in (input('Please input column numbers delimited by comma <1,2>:\\n') or '1,2').split(',')]]][0]), open(input('Input file path:\\n')))).most_common(num) if cnt > 1] for num in [input('\nShow all duplicates (Yes/<N>o)?\\n')[:1].lower()!='y' or None])) or 'No duplicates found.')) for __import__, print, input, zip, int, range, max, set, open, tuple in [[[i for i in ().__class__.__bases__[0].__subclasses__() if i.__name__ == 'BuiltinImporter'][0].load_module('builtins').__dict__[i] for i in ('__import__', 'print', 'input', 'zip', 'int', 'range', 'max', 'set', 'open', 'tuple')]]]", {'__builtins__':{}})
