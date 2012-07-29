import hudson.model.*

def view = Hudson.instance.getView("External")

for(item in view.getItems())
{
    println("$item.name")
}