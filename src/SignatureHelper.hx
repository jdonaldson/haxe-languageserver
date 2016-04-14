using StringTools;

class SignatureHelper {
    // regexes used by the helper. NOT THREAD SAFE!
    static var groupRegex = ~/\$(\d)+/g;
    static var parenRegex = ~/^\((.*)\)$/;
    static var argNameRegex = ~/^(\??\w+) : /;
    static var monomorphRegex = ~/^Unknown<\d+>$/;

    static function getCloseChar(c:String):String {
        return switch (c) {
            case "(": ")";
            case "<": ">";
            case "{": "}";
            default: throw 'unknown opening char $c';
        }
    }

    public static function prepareSignature(type:String):String {
        // replace arrows to ease parsing ">" in type params
        type = type.replace(" -> ", "%");

        // prepare a simple toplevel signature without nested arrows
        // nested arrow can be in () or <> and we don't need to modify them,
        // so we store them separately in `groups` map and replace their occurence
        // with a group name in the toplevel string
        var toplevel = new StringBuf();
        var groups = new Map();
        var closeStack = new haxe.ds.GenericStack();
        var depth = 0;
        var groupId = 0;
        for (i in 0...type.length) {
            var char = type.charAt(i);
            if (char == "(" || char == "<" || char == "{") {
                depth++;
                closeStack.add(getCloseChar(char));
                if (depth == 1) {
                    groupId++;
                    groups[groupId] = new StringBuf();
                    toplevel.add(char);
                    toplevel.add('$$$groupId');
                    continue;
                }
            } else if (char == closeStack.first()) {
                closeStack.pop();
                depth--;
            }

            if (depth == 0)
                toplevel.add(char);
            else
                groups[groupId].add(char);
        }

        // process a sigle type entry, replacing inner content from groups
        // and removing unnecessary parentheses
        function processType(type:String):String {
            type = groupRegex.map(type, function(r) {
                var groupId = Std.parseInt(r.matched(1));
                return groups[groupId].toString().replace("%", "->");
            });
            if (parenRegex.match(type))
                type = parenRegex.matched(1);
            return type;
        }

        // split toplevel signature by the "%" (which is actually "->")
        var parts = toplevel.toString().split("%");

        // get a return or variable type
        var returnType = processType(parts.pop());

        // if there is only the return type, it's a variable
        // otherwise `parts` contains function arguments
        var isFunction = parts.length > 0;

        // format function arguments
        var args = [];
        for (i in 0...parts.length) {
            var part = parts[i];

            // get argument name and type
            // if function is not a method, argument name is generated by its position
            var name, type;
            if (argNameRegex.match(part)) {
                name = argNameRegex.matched(1);
                type = argNameRegex.matchedRight();
            } else {
                name = 'arg$i';
                type = part;
            }

            type = processType(type);

            // we don't need to include the Void argument
            // because it represents absence of arguments
            if (type == "Void")
                continue;

            // if type is unknown, include only the argument name
            if (monomorphRegex.match(type))
                args.push(name);
            else
                args.push('$name:$type');
        }

        // finally generate the signature
        var result = new StringBuf();
        if (isFunction) {
            result.addChar("(".code);
            result.add(args.join(", "));
            result.addChar(")".code);
        }
        if (!monomorphRegex.match(returnType)) {
            result.addChar(":".code);
            result.add(returnType);
        }
        return result.toString();
    }
}
