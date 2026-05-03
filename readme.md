# newt

At the moment, just a simple UI DSL (based on Unreal Engine's Slate, with widgets and slots). You'll see some similarities between this and Slate's macro-based DSL (read up on Slate for what slots are and how they work).

Would be nice to expand this into a full scripting language for UIs, like JavaScript but not bad. See examples in the tests folder.

It would also be nice to maybe have some kind of JSX thing going on, but separate files for layouts and scripts is just fine.

You can run the layout test via the "-l" or "--layout" argument (see main for more).

## Comparison with Slate

Slate:

```cpp
SNew(SVerticalBox)
+SVerticalBox::Slot()
.HAlign(HAlign_Center)
.AutoHeight()
.Padding(0.f, 0.f, 0.f, 20.f)
[
	SNew(SButton)
	.ContentPadding(10.f, 2.f)
	.OnPressed(this, &UMyWidget::ButtonPressed)
	[
		SNew(STextBlock)
		.Text(INVTEXT("Click me"))
	]
]
+SVerticalBox::Slot()
.HAlign(HAlign_Center)
.AutoHeight()
[
	SNew(STextBlock)
	.Text(INVTEXT("Something"))
]
```

newt:

```
VBox
+ halign=center, autoheight=true, padding=(0, 0, 0, 20) (
	Button contentpadding=(10, 2), pressed="self.buttonPressed"
	+(Label text="Click me"))
+ halign=center, autoheight=true (Label text="Something")
```
