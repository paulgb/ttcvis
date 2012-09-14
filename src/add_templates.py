
from jinja2 import Template
from markupsafe import Markup
from os.path import dirname, join
from process_data import load_config

def main():
    config = load_config()
    template_filename = join(dirname(__file__), '../', 'templates', 'main.svg')
    template_file = file(template_filename)
    segments_filename = join(dirname(__file__), '../', 'computed', 'segments.svg')
    outfile_name = join(dirname(__file__), '../', 'svg', 'segments.svg')

    template = Template(template_file.read())
    segments = Markup(file(segments_filename).read())

    outfile = file(outfile_name, 'w')
    stream = template.stream({'segments': segments, 'config': config})
    stream.dump(outfile)
    

if __name__ == '__main__':
    main()

