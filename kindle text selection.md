## patent for the system i think

Title:

**Selection of elements on paginated touch sensitive display**

United States Patent 8952912

Abstract:

Systems and methods are disclosed for selecting portions of media content across two or more pages of the media content with paginated display on a touch sensitive display screen. Selections may be made in either the forward or reverse directions.

Application Number:

13/619177

Publication Date:

02/10/2015

Filing Date:

09/14/2012

Export Citation:

Click for automatic bibliography
generation

Assignee:

Amazon Technologies, Inc.

Primary Class:

[345/173](https://www.freepatentsonline.com/CCL-345-173.html)

Other Classes:

715/863

International Classes:

_**G06F3/041**_; _**G06F3/033**_; _**G06F3/0488**_

Field of Search:

345/169, 345/173, 715/863

View Patent Images:

[Download PDF 8952912](https://www.freepatentsonline.com/8952912.pdf)

US Patent References:

|     |     |     |     |     |
| --- | --- | --- | --- | --- |
| 20130328792 | [Electronic Device with Wrapped Display](https://www.freepatentsonline.com/y2013/0328792.html) | 2013-12-12 | Myers et al. | 345/173 |
| 20120306772 | [Gestures for Selecting Text](https://www.freepatentsonline.com/y2012/0306772.html) | 2012-12-06 | Tan et al. | 345/173 |
| 20110209103 | [MULTI-SCREEN HOLD AND DRAG GESTURE](https://www.freepatentsonline.com/y2011/0209103.html) | 2011-08-25 | Hinckley et al. | 715/863 |

Attorney, Agent or Firm:

EVERSHEDS SUTHERLAND (US) LLP

Claims:

That which is claimed:

1\. A system, comprising:
at least one memory that stores computer-executable instructions;a touch sensitive display screen configured to render a display and detect contact from a contacting element with the at least one touch sensitive display screen;at least one processor configured to control the display on the at least one touch sensitive display screen, receive an indication of contact with the at least one touch sensitive display screen, and access the at least one memory, wherein the at least one processor is configured to execute the computer-executable instructions to:display a first page associated with a media content on the touch sensitive display screen, wherein the media content comprises a sequence of media elements arranged as a sequence of pages, each page comprising one or more media elements;while the first page is displayed, identify a first location on the touch sensitive display screen that has been contacted by the contacting element for a first period of time;identify a first media element corresponding to the first location on the first page;detect movement of the contacting element to a predetermined location on the touch sensitive display screen while the first page is displayed and while the contacting element is in contact with the touch sensitive display screen;highlight one or more elements on the first page corresponding to at least a portion of media elements located between the first location and the predetermined location;determine that the contacting element is in contact with the predetermined location for a second period of time and responsive to detecting the contact for the second period of time, display a second page of the media content and highlight all media elements of the second page;sequentially display one or more pages of the media content every third period of time while the contacting element continues to be in contact with the predetermined location while highlighting all media elements of each of the one or more pages;detect movement of the contacting element to a second location on the touch sensitive display screen and identify a second media element corresponding to the second location on a currently displayed page;remove the highlighting from media elements between the predetermined location and the second location on the currently displayed page, wherein the currently displayed page is different from the first page; andprovide a selection of media elements comprising the first media element, the second media element, and all of media elements between the first media element and second media element.

2\. The system of claim 1, wherein the media elements are at least one of: (i) text; (ii) an image; (iii) a sound; or (iv) a video.

3\. The system of claim 1, wherein the predetermined location is substantially at a top left portion of the touch sensitive display screen and the currently displayed page precedes the first page.

4\. The system of claim 1, wherein the predetermined location is substantially at a bottom right portion of the sensitive display screen and the currently displayed page is subsequent to the first page.

5\. The system of claim 1, wherein providing the selection of media elements further comprises detecting that the contacting element is no longer in contact with the touch sensitive display screen.

6\. The system of claim 1, further comprising displaying a control menu on the touch sensitive display screen when the selection of media elements has been provided.

7\. The system of claim 6, wherein the third period of time is longer than the second period of time.

8\. A method, comprising:
detecting, by an electronic device comprising one or more processors, contact of a contacting element at a first location on a touch sensitive display screen while a first page of media content is displayed on the touch sensitive display screen;identifying a first media element corresponding to the first location, wherein the media content is a sequence of media elements arranged in a sequence of pages;detecting, by the electronic device, movement of the contacting element to a predetermined location of the touch sensitive display screen and contact with the predetermined location for a first period of time while the first page of the media content is displayed;responsive to detecting the contact at the predetermined location for the first period of time while the first page is displayed, displaying, by the electronic device, a second page associated with the media content on the touch sensitive display screen and highlighting all media elements on the second page;detecting contact of the contacting element at the predetermined location for a second period of time while displaying the second page and responsive to detecting the contact at the predetermined location for the second period of time, displaying, by the electronic device, a third page associated with the media content on the touch sensitive display screen and highlighting all media elements on the third page;detecting, by the electronic device, movement of the contacting element to a second location of the touch sensitive display screen and identifying a second media element corresponding to the second location on the third page;removing, by the electronic device, the highlighting from media elements between the predetermined location and the second location on a currently displaced page, wherein the currently displayed page is different from the first page; andproviding a selection of media elements comprising the first media element, the second media element, and all media elements between the first and second media elements.

9\. The method of claim 8, wherein the media elements are at least one of: (i) text; (ii) an image; (iii) a sound; or (iv) a video.

10\. The method of claim 8, wherein the predetermined location is substantially at a top left portion of the touch sensitive display screen and the second page precedes the first page.

11\. The method of claim 8, wherein the predetermined location is substantially at a bottom right portion of the touch sensitive display screen and the second page is subsequent to the first page.

12\. The method of claim 8, wherein the identification of the selection of media elements further comprises detecting that the contacting element is no longer in contact with the touch sensitive display screen.

13\. The method of claim 8, further comprising displaying a control menu on the touch sensitive display screen when the selection of media elements has been identified.

14\. The method of claim 8, wherein highlighting media elements comprises at least one of: (i) bolding the media element; (ii) changing the color of the media element; (iii) italicizing the media element; or (iv) changing a color of a background of the media element.

15\. The method of claim 8, wherein the second period of time is longer than the first period of time.

16\. The method of claim 8, further comprising copying, by the electronic device, the selection of media elements to a memory.

17\. The method of claim 8, wherein detecting contact of a contacting element at the first location comprises detecting the contact of the contacting element at the first location for a third period of time.

18\. The method of claim 8, wherein at least one of the first period of time or the second period of time is configured based at least in part on user input.

19\. At least one non-transitory computer-readable medium comprising computer-executable instructions that, when executed by one or more processors, executes a method comprising:
detecting contact at a first location on a touch sensitive display screen while a first page of a media content comprising a plurality of pages is displayed on the touch sensitive screen;displaying a subsequent page to the first page if contact is detected at a first predetermined location on the touch sensitive display screen and highlighting all media elements of the subsequent page;displaying a prior page to the first page if contact is detected at a second predetermined location on the touch sensitive display screen and highlighting all media elements of the prior page;continuing to display the first page if neither the first nor the second predetermined locations are contacted;detecting contact at a second location on the touch sensitive display screen;removing the highlighting from media elements between one of: (i) the first predetermined location and the second location on the subsequent page, or (ii) the second predetermined location and the second location on the prior page; andproviding a selection of media elements located between the first location on the first page and the second location on a current page of the media content that is displayed.

20\. The at least one non-transitory computer-readable medium of claim 19, wherein the media content is a sequence of media elements and a sequence of pages, each page comprising one or more media elements.

21\. The at least one non-transitory computer-readable medium of claim 20, wherein the media elements are at least one of: (i) text; (ii) an image; (iii) a sound; or (iv) a video.

22\. The at least one non-transitory computer-readable medium of claim 19, wherein the position of at least one of (i) the first predetermined location or (ii) the second predetermined location is based at least in part on one or more of: (i) metadata associated with the media content; (ii) language of the media content; or (iii) orientation of media elements of the media content.

23\. The at least one non-transitory computer-readable medium of claim 19, wherein the first predetermined location is substantially at a bottom right portion of the touch sensitive display screen and the second predetermined location is substantially at a top left portion of the touch sensitive display screen.

24\. The at least one non-transitory computer-readable medium of claim 19, wherein detecting contact at a first location on a touch sensitive display screen comprises detecting the contact for a first period of time.

25\. The at least one non-transitory computer-readable medium of claim 19, wherein detecting contact at a first location on a touch sensitive display screen comprises identifying a first media element of the media content corresponding to the first location.

26\. The at least one non-transitory computer-readable medium of claim 25, wherein detecting contact at a second location on a touch sensitive display screen comprises identifying a second media element of the media content corresponding to the second location.

27\. The at least one non-transitory computer-readable medium of claim 26, wherein providing a selection of media elements comprises identifying the first media element, the second media element and at least a portion of media elements between the first and second media elements as part of the selection of media elements.

Description:

# BACKGROUND

Electronic user devices, such as mobile devices and/or electronic book readers, may have touch based user interfaces, such as touch sensitive displays. These touch sensitive displays may be touched with a finger or other elements to provide input to the user devices. The devices often also display text and/or other types of elements on touch sensitive displays. The text and/or other elements may be displayed in a paginated manner, rather than a scrolling display.

# BRIEF DESCRIPTION OF THE DRAWINGS

The detailed description is set forth with reference to the accompanying figures. In the figures, the left-most digit(s) of a reference number identifies the figure in which the reference number first appears. The use of the same reference numbers in different figures indicates similar or identical items; however, various embodiments may utilize elements and/or components other than those illustrated in the figures.

FIG. 1 is a schematic illustration of an example electronic device with a touch sensitive display that may be configured for paginated display and selection across pages, in accordance with embodiments of the disclosure.

FIG. 2 illustrates a block diagram of the example electronic device of FIG. 1, in accordance with embodiments of the disclosure.

FIGS. 3A, **3** B, and **3** C illustrate an example mechanism for making selections on the touch sensitive display of the electronic device of FIG. 1, in accordance with embodiments of the disclosure.

FIGS. 4A and 4B illustrate a flow diagram representing an example method for selecting elements across pages on the example electronic device of FIG. 1, in accordance with embodiments of the disclosure.

FIGS. 5A, **5** B, **5** C, and **5** D illustrate an example mechanism for selecting text across more than one page in a forward direction, in accordance with embodiments of the disclosure.

FIGS. 6A, **6** B, **6** C, and **6** D illustrate an example mechanism for selecting text across more than one page in a reverse direction, in accordance with embodiments of the disclosure.

FIG. 7 illustrates an example mechanism for selecting text and displaying a control menu, in accordance with embodiments of the disclosure.

# DETAILED DESCRIPTION

Overview

Embodiments of the present disclosure are directed to, among other things, selecting text or other elements on an electronic device, such as an electronic book reader, and more particularly selecting text or other elements across more than one page with paginated displays.

User devices, such as electronic readers, tablet computers, laptop computers, smart phones, and the like, are often used by users to display various forms of media content, such as text and/or pictures. Often times, especially for electronic book readers, the electronic device may be configured to display the media in a paginated fashion, where the elements, such as text, are shown as multiple pages. In other words, text and/or other elements may be segmented into pages, and each page may be predetermined and may be displayed as one or more pages on the electronic displays of the user device. For example, the elements of the media may not be shown in a scrolling fashion, where the elements scroll onto and off of the display of the user device.

In certain embodiments of the disclosure, the electronic device may have a touch sensitive display where a user may touch the surface of the display to provide input to the electronic device. In one aspect, the touch sensitive display may be touched with the user's finger or with any suitable pointing element, such as a pen. The electronic device may be able to detect points on the touch sensitive surface where a user touches the touch sensitive surface. The electronic device may further be configured to detect the dragging of the pointing element and/or finger on the surface of the touch sensitive display. Responsive to detecting the dragging of the finger on the touch sensitive display, the electronic device may be configured to select elements between an initial position where the touch sensitive display was touched and the current position where the touch sensitive display was touched, which may span two or more pages.

In certain embodiments, the touch sensitive user display may have a first predetermined position. This first predetermined position, when touched by a user, may cause the electronic device to move to the next page and select at least a portion of the next page. In certain embodiments, the touch sensitive user display may have a second predetermined position. This second predetermined position, when touched by a user, may cause the electronic device to move to the previous page and select at least a portion of the previous page. The elements of the media content may be selected when the user touches the touch sensitive user display for a predetermined period of time.

In certain further embodiments of the disclosure, the user device may display a next or subsequent page of a media on the touch sensitive display upon detecting a touch at the first predetermined position for at least a first temporal period. Therefore, the user may be able to select text for elements across more than one page by touching an initial location on the touch sensitive user display and dragging his/her finger to the first predetermined position and continue to touch that first predetermined location for at least the first temporal period. The user may then drag his/her finger away from the first predetermined position, after the next page is displayed, before a second predetermined period has lapsed. The electronic device may detect this movement of the finger on the touch sensitive display and, responsive to the movement, may deselect portions of the current displayed page on the touch sensitive display. In effect, the user using the electronic device may select a selection that spans from the initial location where the user touched the touch sensitive display on the first page to a final touch location on the subsequent page. During this time when the user selects a selection, the user may not lift his/her finger from the touch sensitive display screen. In this multipage selection, the user, in effect, may touch the first predetermined position for a first predetermined temporal period to move from the first page to a subsequent page. In certain embodiments, the first predetermined location may be substantially at the bottom right corner of the touch sensitive display screen. In these or other embodiments, the first temporal period may be approximately one to three seconds long, such as one second, two seconds, or three seconds.

Similarly, the electronic device may be configured to make selections across multiple pages where the electronic device initially displays a first page and then was prompted to display a previous page for selecting content on prior pages. In these embodiments, the electronic device may be configured to select displayed elements on the touch sensitive display screen when a user touches a particular location on the touch sensitive display screen and subsequently drags his/her finger away from the particular initial touch location. The user may touch a second predetermined location upon the touch sensitive display screen and, responsive to detecting the touch for a predetermined temporal period at the second predetermined location, the electronic device may display the page previous to the page that is currently displayed on the touch sensitive display screen. When the electronic device changes the display on the touch sensitive display screen responsive to user input, one or more elements of the newly displayed page may be selected as a part of a selection. The user may further move his/her finger on the touch sensitive display screen to select additional elements or to deselect already selected elements. In certain embodiments, the second predetermined location may be at approximately the top left corner of the touch sensitive display screen.

In further embodiments, elements may be selected across more than two display pages. In the case of selecting elements in a forward direction, a user may touch the first predetermined location on the touch sensitive display screen for a predetermined temporal period after a selection has already been made across two or more display pages. Responsive to detecting this touch of the first predetermined location for a second temporal period, the electronic device may display a subsequent page to the page that is currently being displayed. Similar to the case of selection across two pages, at this point, there may be elements selected on the newly displayed page. Therefore, the selection at this point may span three or more pages. In certain embodiments, the second temporal period may be longer than the first temporal period. The user may drag his/her finger across the touch sensitive display screen to select and/or deselect elements on the displayed page.

Similar to selecting elements across two or more pages in the forward direction, the electronic device may be configured to select items across two or more pages in the reverse direction. In these embodiments, the user may touch the second predetermined location on the touch sensitive display screen for a second temporal period after a selection has already been made across two or more display pages. Responsive to detecting the touch by the user on the touch sensitive display screen, the electronic device may continue to select elements on the display and further display the page previous to the current page. In effect, to change the display from the first displayed page to a previous page, the electronic device may detect the user's touch at the second predetermined location for a first temporal period. Subsequent to that initial change of display while selecting elements on the display, the electronic device may display a third page that is previous to the currently displayed page or, in other words, the page that is two pages prior to the initial page. When the electronic device displays the page that is two pages prior to the initial page, it may select elements on that page. The user may drag his/her finger to select and/or deselect elements on the currently displayed page.

In one aspect, the second temporal period may be longer than the first temporal period, so that the user does not accidentally select the prior or later pages unintentionally. In other words, the second temporal period may be provided with a temporal span such that a user may move his or her finger away from either the first predetermined location or the second predetermined location within the span of a second, if the user does not want to select either the prior or subsequent pages. In certain embodiments, the second temporal period may be approximately 1.5 seconds.

This brief introduction, including section titles and corresponding summaries, is provided for the reader's convenience and is not intended to limit the scope of the claims nor the preceding sections. Furthermore, the techniques described above and below may be implemented in a number of ways and in a number of contexts. Several example implementations and contexts are provided with reference to the following figures, as described below in more detail. However, the following implementations and contexts are but a few of many.

Illustrative Architecture

FIG. 1 depicts a schematic illustration of an example electronic device with a touch sensitive display that may be configured for paginated display and selection across pages. The illustrative environment **100** depicts techniques for selecting elements on an electronic device **110** across multiple pages. The electronic device **110** may be configured to interact with a user **120**. The electronic device **110** may further be configured to interact with other elements or other devices via one or more communicative links, such as a connection to the network **130**. In one aspect, electronic device **110** may be configured to download and/or upload media files and/or other media data via the network **130**. The electronic device **110** may include a chassis and/or casing **140**. The electronic device **110** may further include one or more user input interfaces, such as a touch sensitive display screen **150**. Further still, the electronic device **110** may include one or more switches and/or buttons **155** to enable user control of one or more functionalities of the electronic device **110**. The electronic device **110** may further include one or more sensors **160**.

The users **120** may be individuals or other entities, such as corporations, non-profit organizations, for-profit organizations, government organizations, public sector organizations, or any of the aforementioned entities located in this country or foreign countries. The electronic device **110** may be any one of suitable devices that may be configured to user **120** interaction and display of one or more media elements. The electronic device **110**, in certain embodiments, may be a personal user device. For example, the electronic device **110** may include, but is not limited to, a personal computer, a desktop computer, a notebook computer, a laptop computer, a personal digital assistant, an electronic book (ebook) reader, a tablet computing device, a pad computing device, a smart phone, or combinations thereof. While the drawings and/or specification may portray the electronic device in the likeness of an ebook reader and/or tablet computing device, the disclosure is not limited to these devices. Indeed, the systems and methods described herein may apply to any electronic device capable of displaying media elements, such as text, images, and/or sound. The casing **140** of the electronic device **110** may be constructed of any suitable material, such as plastics, metals, ceramics, or combinations thereof. In certain embodiments, the casing **140** may be constructed of thermal plastic materials using injection molding methods.

The one or more sensors **160** may be in the form of input and/or output interfaces, such as microphones, image sensors, accelerometers, gyroscopes, or the like. Microphones may be of any known type including, but not limited to, condenser microphones, dynamic microphones, capacitance diaphragm microphones, piezoelectric microphones, optical pickup microphones, or combinations thereof. Furthermore, the microphones may be of any directionality and sensitivity. For example, the microphones may be omni-directional, uni-directional, cardioid, or bi-directional. Image sensors may be any known device that converts an optical image to an electronic signal. The image sensor may be of any known variety including a charge coupled device (CCD), complementary metal oxide semiconductor (CMOS) sensors, or the like. The image sensor may further be of any pixel count and aspect ratio. The one or more buttons **155** may be actuated by the user to turn on or turn off the electronic device **110**.

The touch sensitive display screen **150** may be any suitable touch sensitive display including, but not limited, to a capacitive panel. The capacitive panel may have a plurality of capacitive cells (not shown) of any shape and size that can have a varying charge associated therewith. The charge on each cell may vary based on the proximity of a pointing device, such as a finger **180**, near one or more of the cells and the variation in charge may be interpreted by the electronic device **110** as an indication of touching the touch sensitive display screen **150**. In other words, a conductive element, such as the finger **180**, may be able to perturb the charge on one or more capacitive cells of the capacitive panel when proximate to those cells. Therefore, the capacitive panel signal can indicate the region on the touch sensitive display screen **150** where an object, such as the finger **180**, is near or touching. The functioning of capacitive panels is well-known, and in the interest of brevity, will not be reviewed here.

The networks **130** may include any one or a combination of different types of suitable communications networks, such as cable networks, the Internet, wireless networks, cellular networks, and other private and/or public networks. Furthermore the networks **130** may include any variety of medium over which network traffic is carried including, but not limited to, coaxial cable, twisted wire pair, optical fiber, hybrid fiber coaxial (HFC), microwave terrestrial transceivers, radio frequency communications, satellite communications, or combinations thereof. While the illustrated example represents the users **120** accessing a website and/or web service over the networks **130**, the described techniques may equally apply in instances where the users **120** interact with the website servers via one or more user devices over a landline phone, via a kiosk, or in any other manner. FIG. 2 illustrates a block diagram of an example electronic device. Referring now to FIG. 2, the electronic device **110** may include one or more processors **200**, one or more input/output (I/O) device interfaces **210**, one or more network interface(s) **220**, one or more sensor interface(s) **230**, and/or one or more memories **250**. In some examples, the processors **200** of the electronic device **110** may be implemented as appropriate in hardware, software, firmware, or combinations thereof. Software or firmware implementations of the processors **200** may include computer-executable or machine-executable instructions written in any suitable programming language to perform the various functions described. Hardware implementations of the processors **200** may be configured to execute computer-executable or machine-executable instructions to perform the various functions described. The one or more processors **200** may include, without limitation, a central processing unit (CPU), a digital signal processor (DSP), a reduced instruction set computer (RISC), a complex instruction set computer (CISC), a microprocessor, a microcontroller, a field programmable gate array (FPGA), or any combination thereof. The electronic device **110** may also include a chipset (not shown) for controlling communications between the one or more processors **200** and one or more of the other components of the electronic device **110**. The one or more processors **200** may also include one or more application-specific integrated circuits (ASICs) or application-specific standard products (ASSPs) for handling specific data processing functions or tasks.

The I/O device(s) or user interface(s), such as the touch sensitive display screen **150**, may be controlled via the one or more I/O device interfaces **210**. The network interfaces(s) **220** may allow the electronic device **110** to communicate via network **130** and/or via other communicative channels. For example, the electronic device **110** may be configured to communicate with stored databases, other computing devices or servers, user terminals, other devices on the networks **130** and/or repositories of media content. The sensor interface(s) **230** may enable the electronic device **110** to receive and interpret signals from the one or more sensors **160**.

The memory **250** may include one or more volatile and/or non-volatile memory devices including, but not limited to, random access memory (RAM), dynamic RAM (DRAM), static RAM (SRAM), synchronous dynamic RAM (SDRAM), double data rate (DDR) SDRAM (DDR-SDRAM), RAM-BUS DRAM (RDRAM), flash memory devices, electrically erasable programmable read only memory (EEPROM), non-volatile RAM (NVRAM), universal serial bus (USB) removable memory, or combinations thereof.

The memory **250** may store program instructions that are loadable and executable on the processor(s) **200**, as well as data generated or received during the execution of these programs. Turning to the contents of the memory **250** in more detail, the memory **250** may include an operating system (O/S) module **252**, an applications module **254**, a media module **256**, a media interface **258**, and/or a media storage module **260**. Each of the modules and/or software may provide functionality for the electronic device **110**, when executed by the processors **200**. The modules and/or the software may or may not correspond to physical locations and/or addresses in the memory **250**. In other words, the contents of each of the modules may not be segregated from each other and may, in fact, be stored in at least partially interleaved positions on the memory **250**.

The operating system module **252** may have one or more operating systems stored thereon. The processors **200** may be configured to access and execute one or more operating systems stored in the operating system module **252** to operate the system functions of the electronic device **110**. System functions, as managed by the operating system module **252**, may include memory management, processor resource management, driver management, application software management, system configuration, and the like. The operating system module **252** may be any variety of suitable operating systems including, but not limited to, Google® Android®, Microsoft® Windows®, Microsoft® Windows® Server®, Linux, Apple® OS-X®, or the like. The application module **254** may contain instructions and/or applications thereon that may be executed by the processors **200** to provide one or more services to the user **120**. These instructions and/or applications may, in certain aspects, interact with the operating system module **252** and/or other modules of the electronic device **110**.

The media module **256** may have stored thereon instructions and/or programs that when executed by the processors **200** may enable the electronic device **110** to access and manage media that may be rendered by the electronic device **110** to the user **120**. In one aspect, the media module **256** and the instructions stored thereon may enable the processors **200** to receive and/or retrieve media from a variety of suitable sources. The sources may include, for example, one or more servers, websites, online bookstores, and/or general distributors of electronic media. For example, the media may be downloaded from a social networking website or from the website of electronic media retailers. In certain aspects, the processors **200**, while running instructions and/or applications stored in the media module **256**, may be configured to invoke the network interfaces **220** to communicate via the network **130** and/or any other suitable communicative channel to access any variety of suitable sources of electronic media.

Instructions and/or applications stored in the media module **256** may further be executed by the processors **200** and thereby enabling the processors **200** to receive electronic media from a source of electronic media, such as via the network **130**. The electronic media may be received in the form of one or more data packets that may be processed using the instructions and/or applications stored in the media module **256**. The one or more data packets may further include extension information, such as parity check bit(s), CRC bit(s) or other transmission quality check information. Upon receiving the electronic media, the instructions and/or applications stored in the media module **256** may be executed by the processors **200** to render the electronic media on one or more user interfaces of the electronic device **110**, such as the touch sensitive display screen **150**. In one aspect, the electronic media may be rendered as text, images, and/or sound. In certain embodiments, the instructions and/or applications of the media module **256** may enable the processors **200** to display the particular page of electronic media, such as on the touch sensitive display screen **150**. The processors **200** may further be configured to display subsequent and/or prior pages of the electronic media based upon inputs received from the user **120**. Therefore, the processors **200** may be configured to modify the rendering, such as the display of electronic media, based on an indication of one or more inputs from the user **120**.

The media interface module **258** may have stored thereon instructions and/or programs that when executed by the processors **200** may enable the electronic device **110** to allow the user **120** to interact with the rendered media. In certain embodiments, the processors **200** may be configured to receive input from the user **120** via the touch sensitive display screen **150** by executing the instructions and/or applications stored in the media interface module **258**. Indeed, the processors **200** may be configured to interact with the I/O device interfaces **210** and/or the sensor interfaces **230** to receive input from the touch sensitive display screen **150** and/or the one or more sensors **160**. In certain embodiments, the processors **200** may receive an indication of the user **120** touching, such as using finger **180**, one or more spots on the touch sensitive display screen **150**. Indeed, the instructions and/or applications stored in the media interface module **258** may interact with the instructions and/or applications stored in the media module **256** to accept user **120** input and modify the rendering of the electronic media based thereon.

In certain embodiments, the instructions and/or applications stored on the media interface module **258** may be executed by the processors **200** to enable the processors **200** to identify particular locations on the touch sensitive display screen **150** that are touched by the finger **180** or other pointing device. The processors **200** may be able to identify whether one or more predefined locations on the touch sensitive display screen **150** is being and/or has been touched by the user **120**, such as by using finger **180**. The processors **200** may further be able to identify the amount of time that the user **120** has touched one or more particular predefined locations on the touch sensitive display screen **150**. For example, the processors **200** may be able to detect if the user **120** has touched the bottom right corner of the touch sensitive display screen **150** for a predefined time span. As another example, the processors **200** may be able to detect if the user **120** has touched the top left corner of the touch sensitive display screen **150** for a second predefined time span. These user interactions with the touch sensitive display screen **150** may be used by the processors **200** to modify elements, such as text or images, that are displayed on the touch sensitive display screen **150** at any point in time.

The media storage module **260** may have stored thereon instructions and/or programs that when executed by the processors **200** may enable the electronic device **110** to store and manage the electronic media that may be available on the electronic device **110**. In certain embodiments, when the media module **256** and the instructions and/or applications stored thereon receive one or more electronic media files, the received one or more electronic media files may be stored in memory **250** by the processors **200** by executing instructions and/or applications of the media storage module **260**.

It will be appreciated that there may be an overlap in the functionality of the instructions stored in the media module **256**, the media interface module **258**, and the media storage module **260**. In fact, the functions of the three modules **256**, **258**, and **260** may interact and cooperate seamlessly under the framework of the electronic device **110**. Indeed, each of the functions described for any of the modules **256**, **258**, and **260** may be stored in any module **256**, **258**, and **260** in accordance with certain embodiments of the disclosure. Further, in certain embodiments, there may be one single module that includes the instructions, programs, and/or applications described within the media module **256**, the media interface module **258**, and the media storage module **260**.

The memory **250**, any databases, and/or any other memory modules, both removable and non-removable, are all examples of computer-readable storage media. For example, computer-readable storage media may include volatile and non-volatile, removable and non-removable media implemented in any method or technology for storage of information such as computer-readable instructions, data structures, program modules, and/or other data.

Illustrative Processes

The electronic device **110** may be accessed by user **120** to view media content on the touch sensitive display screen **150**. In one aspect, the user may use his/her finger **180** to control the display of the media on the touch sensitive display screen **150**. In embodiments of the disclosure, the user may interact with the electronic device **110** to select elements that are displayed on the electronic device **110**. In certain embodiments, the electronic device **110** may be configured to make selections of displayed elements across more than one page of media that may be displayed by the electronic device **110**.

FIGS. 3A, **3** B, and **3** C illustrate an example mechanism for selecting displayed elements on the touch sensitive display of the electronic device **110** in accordance with embodiments of the disclosure. The elements, such as the displayed text, may be in a paginated view. In other words, the display rendered on the touch sensitive display screen **150** may transition from one page to the next and/or previous page, instead of scrolling up and/or down to display other elements of the media content being rendered by the electronic device **110**. Although, the elements displayed on the touch sensitive display screen **150** are shown as text, it will be appreciated that the elements may include any suitable element, such as text, pictures, sounds, or combinations thereof.

In one aspect, a user may place his/her finger **180** on a first location **304** on the touch sensitive display screen **150** and he/she may drag his/her finger **180** from the first location **304** to a second location **308**, by moving the finger **180** in the direction indicated by arrow **312**. In certain embodiments, dragging the finger **180** on the touch sensitive display screen **150** may entail not lifting the finger **180** from the surface of the touch sensitive display screen **150** while moving the finger in the direction indicated by the arrow **312**. When the finger **180** is lifted from the surface of the touch sensitive display screen **150**, the elements, such as text, between the first location **304** and the second location **308** may be selected. In other words, the selection of items on the displayed page may entail the electronic device **110**, and the processors **200** thereon, detecting the motion of the user's **120** finger **180** from an initial selection position to a final selection position on the touch sensitive display screen **150**. In certain embodiments, the selection may be highlighted or otherwise emphasized relative to the non-selected text on the page. The selected text in FIGS. 3B and 3C is shown as highlighted between the first location **304** and the second location **308**.

In certain embodiments, the electronic device **110** and the processors **200** thereon may select elements on the screen when an initial time for touching the first location **304** is detected and determined to exceed a predetermined threshold. In other words, the electronic device **110** may commence selecting elements on the display of the touch sensitive display screen **150** when the electronic device **110** detects that the first location has been touched for a predetermined span of time. The predetermined span of time may be, for example, approximately 1 second.

It will be appreciated that the elements selected, as shown in FIGS. 3A, **3** B, and **3** C, are on a single displayed page as rendered by the electronic device **110** on the touch sensitive display screen **150**. The electronic device **110**, however, may be configured to enable selection of elements as a single selection across more than one page rendered by the electronic device **110**. Referring now to FIGS. 4A and 4B, a flow diagram depicting an example method **400** for selecting elements across more than one page of media content is shown. The method **400** may be performed by the electronic device **110**, in accordance embodiments of the disclosure.

At block **402**, a first page of text may be displayed on the touch sensitive display screen **150**. In one aspect, the display on the touch sensitive display screen **150** may include any suitable element(s) such as text, images, or a combination of text and images. As discussed above, the electronic device **110** and the processors **200** may be configured to receive media files and/or media content from one or more sources, such as a remote media content server via the network **130**. In one aspect, the processors **200** may execute code and/or applications stored in the media module **256** to request and/or receive media content and/or files. In one aspect, the media content and/or files may be received as a stream of data and/or as one or more data packets. The processors **200** may be configured to receive the media data packets and/or streaming data and render the associated media content on the touch sensitive display screen **150** and/or other elements of the electronic device **110**. In certain embodiments, the media content and/or files may be saved on the memory **250** of the electronic device **110**. To do so may involve executing by the processors **200**, code available in the media storage module **260** of the memory **250**. In these embodiments, the media content may be stored in the memory **250** and may be rendered on the touch sensitive display screen **150** of the electronic device **110** by the processors **200** accessing the media content from the memory **250**.

At block **404**, the finger on the screen may be detected, and an initial position of touch may be recorded. The recorded location on the touch sensitive display screen **150** may in certain embodiments be stored or saved on the memory or one or more registers of the processors **200**. In certain embodiments, the initial location of the touch may be stored as a coordinate, such as a two-dimensional coordinate that may indicate the location of the initial touch by the finger **180** on the touch sensitive display screen **150**. In certain embodiments, the electronic device **110** and the processors **200** thereon may detect and/or measure the length of time that the initial location has been touched. The electronic device **110** and the processors **200** thereon may further determine that the length of time that the initial location on the touch sensitive display screen **150** has been touched exceeds a predetermined threshold time span. In these embodiments, the electronic device **110** may commence selecting elements on the display of the touch sensitive display screen **150** when the electronic device **110** detects that the initial location has been touched for a predetermined span of time. The predetermined span of time may be, for example, approximately 1 second. In the same or other embodiments, the electronic device **110** and the processors **200** thereon may begin selecting of items on the display of the touch sensitive display screen **150** if other touch based actions are not detected. For example, if the touch by the finger **180** on the touch sensitive display screen **150** does not indicate an action for the electronic device **110** to perform, such as “flipping” the displayed page or changing the displayed media content, then the electronic device **110** and the processors **200** may interpret the touch to be an indication of the user's desire to select elements on the touch sensitive display screen **150**.

At block **406**, it may be determined if the finger is moving. If at block **406**, it is determined that the finger is not moving, then the method **400** may return to block **404** to continue detecting the finger **180** and the position of the finger **180**. In the context of determining if the finger **180** is moving, it should be noted that, in many cases, the threshold of detecting the motion of the finger **180** may exceed the ability of a human to control the motion of his/her finger **180**. In other words, the finger **180** may have some positional jitter associated therewith that may not be readily controllable by the user **120**, but may be detected by the electronic device **110**. Accordingly, the electronic device **110** may ascertain that the finger **180** is in motion if the movement of the finger **180** exceeds a predetermined spatial threshold. This predetermined spatial threshold may be related to a human's ability to control the motion of his/her finger on the surface of the touch sensitive display screen **150**.

At block **406**, if it is determined that the finger **180** is moving, then the method **400** may proceed to block **408**, where the text and/or elements on the display between the initial position and the current position may be highlighted. Therefore, the processors **200** may detect the current position of the finger **180** on the touch sensitive display screen **150** and may determine elements to select and/or highlight based at least in part on the initial location and the currently detected location of the finger **180**.

At block **410**, it may be determined if the current position is at a first predetermined location for a first temporal time period. If at block **410**, the current location of the finger **180** is determined to not be at a first predetermined location or not at the first predetermined location for at least a first temporal period, then the method **400** may proceed to block **412** to determine if the current position is at a second predetermined location for the first temporal time period. If at block **412**, the current location of the finger **180** is determined to not be at the second predetermined location or not at the second predetermined location for at least a first temporal period, then the method **400** may proceed to block **414** to determine if the finger is still touching the screen. If it is determined that the finger **180** is still touching the screen at block **414**, then the method **400** may return to block **408** and continue to display highlighted text between the initial position and the current position of touch, corresponding to selected elements on the display of the touch sensitive display screen **150**. If at block **414**, it is determined that the finger **180** is no longer touching the surface of the touch sensitive display screen **150**, then the method **400** may proceed to block **416**, where a control menu may be displayed. In one aspect, the control menu may be displayed on and/or near the selected and highlighted displayed elements. The control menu may offer the user one or more choices of actions that the user may perform. In certain embodiments, the actions offered by the displayed control menu may include actions that may be performed on the selected elements, such as copying the selected elements to a buffer or a clipboard. It should be noted that the control menu displayed on the touch sensitive display screen **150** at block **416** may be displayed with a selection of elements that do not span more than one page of the media content rendered by the electronic device **110**.

If at block **410**, it is determined that the current position is at the first predetermined location for a first temporal period, then at block **418**, the next page may be displayed. In other words, if the electronic device **110** and the processors **200** thereon detect the touching of a particular location on the touch sensitive display screen **150**, then the electronic device **110** may change the display to display the subsequent page of the media content on the touch sensitive display screen **150**. Of course, if the last page of the media content is displayed at the point when it is determined that the user has touched the first predetermined location for a first temporal period, then the display may not proceed to a subsequent page and, instead, may remain on the last page of the media content.

It will be appreciated that at block **418**, when the display proceeds to the subsequent page of the media content, some or all of the elements, such as text, on the subsequent page, when displayed, may be selected as part of the selection. To deselect elements of the subsequent page, the user **120** may move his/her finger away from the first predetermined location as is described in more detail below. In certain embodiments, the first predetermined location may be at approximately the bottom right corner of the touch sensitive display screen **150**. In these embodiments, the user **120** may, therefore, place his/her finger **180** at approximately the bottom right corner of the touch sensitive display screen **150**, and responsive to detecting the touch of the finger **180** at this location for the first predetermined temporal period, may display the next page and select all of the elements on the subsequent page of the touch sensitive display screen **150**.

If at block **412**, it is determined that the current position is at the second predetermined location for a first temporal period, then at block **420**, the prior page may be displayed. In other words, if the electronic device **110** and the processors **200** thereon detect the touching of a particular location on the touch sensitive display screen **150**, then the electronic device **110** may change the display to display the prior page of the media content on the touch sensitive display screen **150**. Of course, if the first page of the media content is displayed at the point when it is determined that the user has touched the second predetermined location for a first temporal period, then the display may not proceed to the prior page and, instead, may remain on the first page of the media content.

It will be appreciated that at block **420**, when the display proceeds to the prior page of the media content, some or all of the elements, such as text, on the previous page, when displayed, may be selected as part of the selection. To deselect elements of the previous page, the user **120** may move his/her finger away from the second predetermined location as is described in more detail below. In certain embodiments, the second predetermined location may be at approximately the top left corner of the touch sensitive display screen **150**. In these embodiments, the user **120** may, therefore, place his/her finger **180** at approximately the top left corner of the touch sensitive display screen **150**, and responsive to detecting the touch of the finger **180** at this location for the first predetermined temporal period, may display the previous page and select all of the elements on the previous page of the touch sensitive display screen **150**.

From either of blocks **418** or **420**, the method **400** may proceed to block **422** of FIG. 4B, where text and/or other elements between the initial touch position and the current touch position may be highlighted or otherwise emphasized to indicate their inclusion within the selection. For example, if the finger **180** is at approximately the top left corner of the touch sensitive display screen **150** and block **422** is reached via block **420**, then in certain embodiments, the current selection may include some or all elements on an initial page, as well as all of the elements on the previous page, or the page prior to the initial page of display. As another example, if the finger **180** is at approximately the bottom right corner of the touch sensitive display screen **150** and block **422** is reached via block **418**, then in certain embodiments, the current selection may include some or all of the elements on an initial page, as well as all of the elements on the subsequent page, or the page after the initial page of display.

At block **424**, it may be determined if the finger is moving. If the finger is moving, then the method **400** may return to block **408** to highlight or otherwise emphasize text and/or other elements between the initial touch position and the current touch position. It should be noted that at this point the selected elements span more than one page of display. Indeed the selected portions displayed at block **408** are the portions of the selection that are visible on the display, or the selected elements on the currently displayed page on the touch sensitive display screen **150**.

If at block **424**, it is determined that the finger is not moving, then at block **426**, it may be determined if the current position is at the first predetermined position for a second temporal period. In certain embodiments, the second temporal period may be different from the first temporal period. In the same or different embodiments, the second temporal period may be longer in time than the first temporal period. For example, the first temporal period may be approximately 1 second long and the second temporal period may be 1.5 seconds long. In other embodiments, the first and second temporal periods may be substantially the same span of time.

If at block **426** it is determined that the current position of the finger **180** is at the first predetermined location for a second temporal period, then the touch sensitive display screen **150** may display the next page at block **428**. Of course, if the last page of the media content is displayed at the point when it is determined that the user **120** has touched the first predetermined location for a second temporal period, then the display may not proceed to a subsequent page and, instead, may remain on the last page of the media content. When the next and/or subsequent page is displayed, portions or all of the elements on the newly displayed page may be selected and/or highlighted as part of selected elements. The method **400** may proceed to block **422**, where text and/or other elements between the initial touch position and the current touch position may be highlighted or otherwise emphasized to indicate their inclusion within the selection. Indeed, only the portion of the selected elements that are currently shown on the touch sensitive display screen **150** may be shown as selected and highlighted and/or emphasized in other ways. Therefore, there may be selected elements on one or more other pages of the media content that are not currently displayed and therefore are not currently displayed as highlighted.

If at block **426** it is determined that the current position of the finger **180** is not either at the first predetermined location or not at the first predetermined location for a second temporal period, then at block **430**, it may be determined if the current position of the finger is at the second predetermined location for the second temporal period. If it is determined that the current position of the finger **180** is at the second predetermined location for a second temporal period, then the touch sensitive display screen **150** may display the previous page at block **432**. Of course, if the first page of the media content is displayed at the point when it is determined that the user **120** has touched the second predetermined location for a second temporal period, then the display may not proceed to a previous page and, instead, may remain on the first page of the media content. When the previous and/or prior page is displayed, portions or all of the elements on the newly displayed page may be selected and/or highlighted as part of the selected elements. The method **400** may proceed to block **422**, where text and/or other elements between the initial touch position and the current touch position may be highlighted or otherwise emphasized to indicate their inclusion within the selection. Indeed, only the portion of the selected elements that are currently shown on the touch sensitive display screen **150** may be shown as selected and highlighted and/or emphasized in other ways. Therefore, there may be selected elements on one or more other pages of the media content that are not currently displayed and therefore are not currently displayed as highlighted.

If at block **430**, it is determined that the current position of the finger **180** is neither at the second predetermined location nor at the second predetermined location for a second temporal period, then at block **434**, it may be determined if the finger is still touching the touch sensitive display screen **150**. If the finger is still touching the touch sensitive display screen, then the method **400** may return to block **422**, where text and/or other elements between the initial touch position and the current touch position may continue to be highlighted or otherwise emphasized to indicate their inclusion within the selection. Indeed, only the portion of the selected elements that are currently shown on the touch sensitive display screen **150** may be shown as selected and highlighted and/or emphasized in other ways. Therefore, there may be selected elements on one or more other pages of the media content that are not currently displayed and therefore are not currently displayed as highlighted.

If at block **434**, it is determined that the finger **180** is no longer touching the surface of the touch sensitive display screen **150**, then at block **436**, a control menu may be displayed. In one aspect, the control menu may be displayed on and/or near the selected and highlighted displayed elements. The control menu may offer the user one or more choices of actions that the user may perform. In certain embodiments, the actions offered by the displayed control menu may include actions that may be performed on the selected elements, such as copying the selected elements to a buffer or a clipboard. It should be noted that the control menu displayed on the touch sensitive display screen **150** at block **436** may be displayed with a selection of elements that span more than one page of the media content rendered by the electronic device **110**.

It will be appreciated that the user **120**, in certain embodiments, may choose to make a selection of elements across more than two pages, and the method **400** enables the selection of elements across any number of pages. The user **120** may touch an initial page at an initial location to start selecting elements on the first displayed page in accordance with the processes described in conjunction with blocks **406** and **408**. The user **120** may next wish to select elements as part of the current selection on either a subsequent or prior page. In this case, the processes of either blocks **410**, **418**, and **422** or blocks **412**, **420**, and **422** may be invoked to make a selection on a subsequent or prior page, respectively. At this point, if the user **120** wishes to make a selection on a further subsequent page, the user **120** may invoke the processes of blocks **426**, **428**, and **422** to continue to make selections on yet a third page. Indeed, if the user **120** holds his/her finger **180** at the first predetermined position for several second temporal periods, then several pages may be selected in the forward direction and of the media content, such as a fourth page, fifth page, and/or so forth. Alternatively, the user **120** may move his/her finger away from the first predetermined location at block **424** and without lifting his/her finger **180** from the touch sensitive display screen **150**, may move his/her finger back to the first predetermined location, and thereby invoke the processes of blocks **410**, **418**, and **422** a second or more times to display a subsequent page. It will be appreciated that the method **400** may proceed via any combination of blocks **410**, **418**, and **422** and/or blocks **426**, **428**, and **422** to select elements in a forward direction, or otherwise on one or more subsequent pages of the media content. Similarly, it will be appreciated that the method **400** may proceed via any combination of blocks **412**, **420**, and **422** and/or blocks **430**, **432**, and **422** to select elements in a reverse direction, or otherwise on one or more previous pages of the media content.

It should further be noted that in blocks **418**, **420**, **428**, and **432** the display on the touch sensitive display screen **150** may change based at least in part on the detection of the finger **180** on the surface of the touch sensitive display screen **150** at a predetermined location for a predetermined time. The predetermined locations may be, as stated above, at the top left and the bottom right corners of the touch sensitive display screen **150**. This location of the first and second predetermined locations may be particularly intuitive to users **120** for most Indo-European languages, where text is typically read in a left to right and top to bottom direction. However, in certain other embodiments, the first and second locations may be at other points on the surface of the touch sensitive display screen **150** based on one or more of the language, display style, and/or textual direction. For example, some text may be read in a top to bottom direction. In these cases, the first predetermined location may be at approximately the bottom center of the touch sensitive display screen **150**, and the second position may be at approximately the top center of the touch sensitive display screen **150**. In certain embodiments, the electronic device **110** and the processors **200** thereon may determine based at least in part on the language and/or the layout of text or other elements in the media content, the points of the first and/or second predetermined locations on the touch sensitive display screen **150**.

The language and/or layout of the text may, in some cases, may be ascertained by the electronic device **110** and the processors **200** thereon from metadata associated with the media content and/or media files displayed on the electronic device **110**. Therefore, the processors **200**, in certain embodiments, may be configured to receive metadata associated with the media content and parse this metadata to determine the points of the first and second predetermined locations on the touch sensitive display screen **150**. The metadata may be in the form of one or more data packets that may be received by the processors **200** via the network **130** or other communications channels. In certain embodiments, the metadata may be received by the processors **200** concurrently and/or as part of the media content and/or files. In other embodiments, the metadata may be received asynchronously from the media content, such as at a time after receiving the media content, such as from a separate server and/or website. Alternatively, the processors **200** may receive media files with metadata associated with the location of the first and second predetermined locations and may not need to make a determination of the position on the touch sensitive display screen **150** of the first and second predetermined locations. Instead, the positions of the predetermined locations may be ascertained directly from received metadata associated with the displayed media content.

It will be appreciated that in blocks **418**, **420**, **428**, and **432**, the display on the touch sensitive display screen **150** may change based at least in part on detecting the location of the finger **180** at a predetermined location for a predetermined span of time. Indeed, the first time the finger **180** is detected at either a first or a second predetermined location, the electronic device **110** may wait for a first predetermined span of time before the display is modified. If the user **120** keeps his/her finger **180** at that location for the second temporal period, then the display and/or selections may be modified again. It will be appreciated that in certain embodiments, the second temporal period may be longer than the first temporal period to prevent accidental selection and/or display of a previous and/or subsequent page by the user **120**. Once a first page is “flipped,” either forward or backward, the finger **180** remains at or is otherwise still touching the predetermined location associated with the “flip.” Indeed, to prevent a subsequent flip, the user has to move his/her finger **180** away from the predetermined location. To allow the user to look at the display, think about the selections he/she wishes to make, and potentially move his/her finger away from the predetermined location on the touch sensitive display screen **150**, additional time, relative to the first temporal period, may be allotted to the second temporal period.

It should be noted, that the method **400** may be modified in various ways in accordance with certain embodiments of the disclosure. For example, one or more operations of the method **400** may be eliminated or executed out of order in other embodiments of the disclosure. For example, the order of blocks **410** and **412** may be reversed in accordance with certain embodiments of the disclosure. Similarly, the order of blocks **426** and **430** may be reversed in accordance with certain embodiments of the disclosure. Additionally, other operations may be added to the method **400** in accordance with other embodiments of the disclosure.

Referring now to FIGS. 5A, **5** B, **5** C, and **5** D, an example mechanism is discussed for selecting text across more than one page in a forward direction on the electronic device **110** in accordance with embodiments of the disclosure. In particular, FIG. 5A illustrates an example first page on the touch sensitive display screen **150**. FIG. 5B illustrates the same example page as FIG. 5A, with portions of elements on the screen selected, in accordance with embodiments of the disclosure. FIG. 5C illustrates an example second page, subsequent to the example first page of FIGS. 5A and 5B. FIG. 5D illustrates an example third page, subsequent to the example second page of FIG. 5C. It will be understood that while an example media content, namely the United States Declaration of Independence, is displayed on the touch sensitive display screen **150**, any suitable media content may be displayed. In certain embodiments, the media content may include any combination of text, images, video, and/or sound. The media content may have multiple pages that may be displayed by the electronic device **110** and associated processors **200** as one or more pages at a time in a paginated manner on the touch sensitive display screen **150**.

The touch sensitive display screen **150** is shown with approximate locations of a first predetermined location **510** and a second predetermined location **520** indicated. In one aspect, the touch sensitive display screen **150** and the processors **200** may detect contact by the finger **180** on the touch sensitive display screen **150** at an initial touch location **530**. In certain embodiments, the processors **200** may detect this touch at the location **530** to last longer than a predetermined temporal period. The processors **200** may further detect motion of the finger **180** dragging across the touch sensitive display screen **150** from the initial touch location **530** to the first predetermined location **510**, as depicted by arrow **534**. The processors **200** may further detect the finger **180** to be at the first predetermined location **510** for at least a first temporal period.

Responsive to touching the first predetermined location **510** for a first predetermined period, the electronic device **110** and associated processors **200** may display the second and subsequent page on the touch sensitive display screen **150**, as shown in FIG. 5C. At this point, all of the elements, such as text, on the second displayed page may be highlighted and/or otherwise emphasized. Therefore, elements of the media content may be selected, at this point, on both the first page, as shown in FIG. 5B, and on the second page, as shown in FIG. 5C. If the user **120** holds his/her finger **180** at the first predetermined position **510** for a second temporal period, then the display may further change to the next or third page, as shown in FIG. 5D. At this point, the user **120** may move his/her finger **180** along the surface of the touch sensitive display screen **150** from the first predetermined location **510** to a final location **548** as depicted by arrow **544** to deselect portions of the third page. As a result, elements on a first, second, and third page of the media content may be selected by the user **120**, as shown in FIGS. 5B, **5** C, and **5** D.

It will be understood that while the first predetermined location is depicted at approximately the bottom right corner of the touch sensitive display screen **150**, the first predetermined location may be at any appropriate point on the touch sensitive display screen **150**, such as at any point near the bottom of the touch sensitive display screen **150** or proximate to the last word and/or element of the currently displayed page. Similarly, while the second predetermined location is depicted at approximately the top left corner of the touch sensitive display screen **150**, the second predetermined location may be at any appropriate point on the touch sensitive display screen **150**, such as at any point near the top of the touch sensitive display screen **150** or proximate to the first word and/or element of the currently displayed page. As described above, in certain embodiments, the position on the touch sensitive display screen **150** of the first and second predetermined locations may be ascertained by the processors **200** based at least in part on any variety of metadata associated with the media content. Referring now to FIGS. 6A, **6** B, **6** C, and **6** D, an example mechanism is discussed for selecting text across more than one page in a reverse direction on the electronic device **110** in accordance with embodiments of the disclosure. In particular, FIG. 6A illustrates an example first page on the touch sensitive display screen **150**. FIG. 6B illustrates an example second page, prior to the example first page of FIG. 6A. FIG. 6C illustrates an example third page, prior to the example second page of FIG. 6B. FIG. 6D illustrates the same example page as FIG. 6C, with portions of elements on the screen selected, in accordance with embodiments of the disclosure. It will be understood that while an example media content, namely the United States Declaration of Independence, is displayed on the touch sensitive display screen **150**, any suitable media content may be displayed. In certain embodiments, the media content may include any combination of text, images, video, and/or sound. The media content may have multiple pages that may be displayed by the electronic device **110** and associated processors **200** as one or more pages at a time in a paginated manner on the touch sensitive display screen **150**.

The touch sensitive display screen **150** is shown with approximate locations of a first predetermined location **610** and a second predetermined location **620** indicated. In one aspect, the touch sensitive display screen **150** and the processors **200** may detect contact by the finger **180** on the touch sensitive display screen **150** at an initial touch location **630**. In certain embodiments, the processors **200** may detect this touch at the location **630** to last longer than a predetermined temporal period. The processors **200** may further detect motion of the finger **180** dragging across the touch sensitive display screen **150** from the initial touch location **630** to the second predetermined location **620**, as depicted by arrow **634**. The processors **200** may further detect the finger **180** to be at the second predetermined location **620** for at least a first temporal period.

Responsive to touching the second predetermined location **620** for a first predetermined period, the electronic device **110** and associated processors **200** may display the second and prior page on the touch sensitive display screen **150**, as shown in FIG. 6B. At this point, all of the elements, such as text, on the second displayed page may be highlighted and/or otherwise emphasized. Therefore, elements of the media content may be selected, at this point, on both the first page, as shown in FIG. 6A, and on the second page, as shown in FIG. 6B. If the user **120** holds his/her finger **180** at the second predetermined position **620** for a second temporal period, then the display may further change to the previous or third page, as shown in FIG. 6C. At this point, the user **120** may move his/her finger **180** along the surface of the touch sensitive display screen **150** from the first predetermined location **610** to a final location **648** as depicted by arrow **644** to deselect portions of the third page. As a result, elements on a first, second, and third page of the media content may be selected by the user **120**, as shown in FIGS. 6A, **6** B, and **6** D. Referring now to FIG. 7, an example mechanism is discussed for selecting text and displaying a control menu associated with a selection on the electronic device **110** in accordance with embodiments of the disclosure. A block of selected text **704** between a first location **710** and a second location **720** on the touch sensitive display screen **150** may be selected using any variety of methods and/or mechanisms described herein. While the selection **704** is depicted on a single page of the media content, the control menu associated with this embodiment may apply to selections that span more than one page of the rendered media content. When the user **120** lifts his/her finger **180** from the touch sensitive display screen **150**, the one or more processors **200** of the electronic device **110** may render a control menu **740** on the touch sensitive display screen **150** on or in relative proximity to the selection **704**. The control menu **740** may have one or more control buttons and/or virtual control buttons, such as “Select” button **744**, “Add Notes” button **748**, and/or “Options” button **752**. The example buttons **744**, **748**, **752** are representative in nature, and it will be appreciated that there may be any variety and/or number of buttons that may be displayed on the control menu **740**. When one or more of the control buttons are selected, such as by touching with finger **180**, the electronic device **110** may perform one or more actions that correspond to the selected buttons **744**, **748**, **752**. For example, the processors **200** may be configured to add a note to the selection if the button “Add Notes” **748** is selected by the user **120**.

Embodiments may be provided as a computer program product including a non-transitory machine-readable storage medium having stored thereon instructions (in compressed or uncompressed form) that may be used to program a computer (or other electronic device) to perform processes or methods described herein. The machine-readable storage medium may include, but is not limited to, hard drives, floppy diskettes, optical disks, CD-ROMs, DVDs, read-only memories (ROMs), random access memories (RAMs), EPROMs, EEPROMs, flash memory, magnetic or optical cards, solid-state memory devices, or other types of media/machine-readable medium suitable for storing electronic instructions. Further, embodiments may also be provided as a computer program product including a transitory machine-readable signal (in compressed or uncompressed form). Examples of machine-readable signals, whether modulated using a carrier or not, include, but are not limited to, signals that a computer system or machine hosting or running a computer program can be configured to access, including signals downloaded through the Internet or other networks. For example, the distribution of software may be an Internet download.

Although embodiments have been described in language specific to structural features and/or methodological acts, it is to be understood that the disclosure is not necessarily limited to the specific features or acts described. Rather, the specific features and acts are disclosed as illustrative forms of implementing the embodiments. Conditional language, such as, among others, “can,” “could,” “might,” or “may,” unless specifically stated otherwise, or otherwise understood within the context as used, is generally intended to convey that certain embodiments could include, while other embodiments do not include, certain features, elements, and/or steps. Thus, such conditional language is not generally intended to imply that features, elements, and/or steps are in any way required for one or more embodiments or that one or more embodiments necessarily include logic for deciding, with or without user input or prompting, whether these features, elements, and/or steps are included or are to be performed in any particular embodiment.

[<\- Previous Patent (Electronic device wi...)](https://www.freepatentsonline.com/8952911.html)   \|   [Next Patent (Display device and d...) ->](https://www.freepatentsonline.com/8952913.html)

© 2004-2026 FreePatentsOnline.com. All rights reserved.
[Privacy Policy\\
& Terms of Use.](https://www.freepatentsonline.com/privacy.html)

## kindle paperwhite manual

[image]
Kindle User’s Guide 2

## Contents

## Contents

Chapter 1 Getting Started ......................................................................................................................... 5
Registering your Kindle ............................................................................................................................ 5
Kindle controls ............................................................................................................................................. 5
Touchscreen interface ............................................................................................................................... 6
Keyboard ............................................................................................................................................................................... 6
Tap zones .............................................................................................................................................................................. 7
Toolbars................................................................................................................................................................................. 8
Status indicators ........................................................................................................................................ 11
Wireless status indicators .......................................................................................................................................... 11
Battery status indicator ............................................................................................................................................... 12
Activity indicator............................................................................................................................................................. 12
Parental Controls indicator........................................................................................................................................ 12
Setting up your Kindle Paperwhite .................................................................................................... 12
Network connectivity ................................................................................................................................................... 12
Special Offers and Sponsored Screensavers.................................................................................... 13
Screensaver ....................................................................................................................................................................... 13
Special Offer banners .................................................................................................................................................... 13
Chapter 2 Acquiring & Managing Kindle Content ......................................................................... 14
Shop the Kindle Store anytime, anywhere ....................................................................................... 14
Recommended content............................................................................................................................ 14
Device and Cloud storage ....................................................................................................................... 15
Removing items from your Kindle ...................................................................................................... 15
Periodicals .......................................................................................................................................................................... 15
Managing your Kindle Library ............................................................................................................. 16
Cloud Collections............................................................................................................................................................. 17
Chapter 3 Reading Kindle Documents ............................................................................................... 18
Understanding Kindle display technology....................................................................................... 18
Customizing your text display .............................................................................................................. 18
Comic and manga books ......................................................................................................................... 18
Children's books ........................................................................................................................................ 18
Zooming images ......................................................................................................................................... 18
Panning and zooming tables ................................................................................................................. 19
Interacting with your documents ........................................................................................................ 19
About This Book .............................................................................................................................................................. 19
Kindle User’s Guide 3

## Contents

Dictionary ........................................................................................................................................................................... 19
Search ................................................................................................................................................................................... 20
Notes and highlights ...................................................................................................................................................... 21
Bookmarks ......................................................................................................................................................................... 21
Footnotes ............................................................................................................................................................................ 22
Before you go... ................................................................................................................................................................. 22
X-Ray .............................................................................................................................................................. 22
Word Wise .................................................................................................................................................... 22
Vocabulary Builder ................................................................................................................................... 23
Kindle FreeTime ........................................................................................................................................ 23
Setting up Kindle FreeTime ....................................................................................................................................... 23
Using Kindle FreeTime ................................................................................................................................................. 24
Managing your Amazon household .................................................................................................... 24
Goodreads on Kindle ................................................................................................................................ 25
Time to Read ............................................................................................................................................... 27
Navigating a book ...................................................................................................................................... 27
Kindle Page Flip ............................................................................................................................................................... 27
Go To button ...................................................................................................................................................................... 28
Chapter 4 Getting More From Your Kindle Paperwhite ............................................................. 29
Carrying and reading personal documents ..................................................................................... 29
Reading Kindle content on other devices......................................................................................... 29
Sharing comments via social networks............................................................................................. 29
Using your Kindle with your computer ............................................................................................. 30
Using the Experimental Web Browser .............................................................................................. 30
Web Browser Menu ....................................................................................................................................................... 30
Bookmarks ......................................................................................................................................................................... 31
Downloading files ........................................................................................................................................................... 31
Chapter 5 Settings .................................................................................................................................... 32
Customizing your Kindle settings ....................................................................................................... 32
The Settings contextual menu .............................................................................................................. 34
Chapter 6 Finding Additional Assistance ........................................................................................ 35
Appendix A Product Information ........................................................................................................ 36
Safety and Compliance Information ................................................................................................... 36
Maintaining Your Kindle Device .......................................................................................................... 36
Servicing Your Device .............................................................................................................................. 36
Battery Safety .............................................................................................................................................. 36
Kindle User’s Guide 4

## Contents

Other Safety Considerations.................................................................................................................. 37
Wireless Safety and Compliance .......................................................................................................... 37
Turn Off Wireless When Flying ............................................................................................................ 37
Using Your Kindle Around Other Electronic Devices ................................................................... 37
Steps to Minimize Interference ............................................................................................................ 38
Watch for Signs ........................................................................................................................................... 38
FCC Compliance Statement .................................................................................................................... 38
Information Regarding Exposure to Radio Frequency Energy ................................................ 39
Canadian Compliance Statement ......................................................................................................... 39
IEEE 1725 Battery Safety Statement .................................................................................................. 39
EU Conformity ............................................................................................................................................. 40
CE SAR Compliance ................................................................................................................................... 40
Recycling Kindle Properly...................................................................................................................... 40
Product Specifications ............................................................................................................................. 40
LEGAL TERMS .............................................................................................................................................. 41
ONE-YEAR LIMITED WARRANTY ......................................................................................................... 41
Warranty Provider ......................................................................................................................................................... 42
Additional Information ................................................................................................................................................ 43
Patent Notices ............................................................................................................................................. 43
Copyright, Trademark and Other Notices ........................................................................................ 43
Kindle User’s Guide 5
Chapter 1
Getting Started
Chapter 1
Getting Started
Welcome to your new Kindle Paperwhite. This short guide will familiarize you with all of the
features and functionality of your Kindle. Some Kindle features may not be available based on
your country of residence or location. Please visit http://www.amazon.com/devicesupport
for more information about specific features.

Registering your Kindle
If you bought your Kindle online using your Amazon account, it is already registered to you.

To verify, tap the Home button and look for your Amazon user name in the upper left corner
of the Home screen. If it says My Kindle or shows the name of a previous owner instead of
your own Amazon account name, you'll need to register it. See Setting up your Kindle
Paperwhite in this chapter for instructions on setting up and registering your Kindle.

Kindle controls
You need to learn only a few simple controls to use your Kindle Paperwhite.

[image]
Kindle User’s Guide 6
Chapter 1
Getting Started
Power button: To turn your Kindle on, press the Power button. If you need to turn off your
Kindle screen, press and hold the Power button for 7 seconds until the Power dialog displays
and then select Screen Off.

Your Kindle will automatically go into sleep mode after a few minutes of inactivity and a
screensaver displays. This static screensaver uses no battery power. To put your Kindle in
sleep mode, press and release the Power button. To wake up your Kindle, press and release
the Power button.

If your Kindle does not power on or is unresponsive during use and you need to restart it,
press and hold the Power button for 7 seconds until the Power dialog displays and then select
Restart. If the Power dialog does not display, press and hold the Power button for 20 seconds.

Micro-USB/power port: You can use the supplied USB cable to connect your Kindle to a
computer for charging the battery and transferring files. To charge your Kindle from a power
outlet, you will need a compatible AC adapter (sold separately) for the USB cable.

When your Kindle is charging, a lightning bolt appears on the battery icon at the top of the
Home screen. The indicator light on the bottom edge will turn amber while the battery is
charging and green when it is fully charged. Charging should take less than four hours using a
Kindle AC adapter. Charging using 3rd party adapters or via USB should take less than four
hours, but may take longer depending on the capability of the hardware.

You can still use your Kindle while it is connected to your computer and charging via USB. To
do so, unmount or eject it so that your Kindle exits USB drive mode.

 Windows: Right-click on the "Safely remove hardware" icon in the lower right-hand corner of
the task bar and follow the onscreen instructions to remove your Kindle.

 Mac OS X: Click the Eject button next to the Kindle in any Finder window, or drag it from the
Desktop to the Trash.

Your Kindle will then exit USB drive mode. Your Kindle will continue to charge in this mode. If
the charge indicator light on the bottom edge of the Kindle does not come on, make sure that
the USB cable is fully inserted into your Kindle and into the USB port of the computer. If your
Kindle is still not charging, try another USB port or electrical outlet.

Note that if your Kindle is plugged into a low-powered USB port—such as those found on
some keyboards and older computers—it will not receive enough power to charge.

Touchscreen interface
Your Kindle Paperwhite features a touchscreen interface that enables you to perform many
tasks with just a tap or swipe of a finger. To select an item, simply tap it. For example, tap a
book cover or title on your Home screen to open the book, or tap a button to perform that
button's action.

Keyboard
Your Kindle Paperwhite has an onscreen keyboard. When you tap within the Search field or
begin other actions that require you to type in information, the keyboard automatically
displays at the bottom of the screen. Tap the keys to enter your selection and use the
appropriate buttons to continue on to the next action. As you type, word suggestions based
upon your entries will appear above the keyboard. Tap the word you want to select.

Kindle User’s Guide 7
Chapter 1
Getting Started
Keyboard tips:
 Tap the key to enter numbers or symbols.

 Tap the to return to the regular keyboard.

 Tap the Shift key to enter uppercase characters. Tap the Shift key twice to enter
all-cap mode, and tap it once to exit the mode.

 To select a keyboard for a different language, tap the Menu button and select Settings. On the
Settings page, select Device Options, Language and Dictionaries, then Keyboards.

 To enter diacritics and special characters using the keyboard, press and hold the base letter’s
key. For example, press and hold the "n" to display ǹ, ñ, or ň.

 A Globe key is added to your keyboard when you have selected multiple languages. To
select a different keyboard, tap the Globe key.

Tap zones
The EasyReach feature of your Kindle lets you effortlessly turn pages in a book or periodical
while holding the device with just one hand. Tapping almost anywhere in the display area will
take you to the next page; the area is large enough to be tapped whether you hold the device
with your left or right hand. Tap the left side of the screen to go to the previous page. The
EasyReach tap zones differ depending on whether your Kindle is in portrait or landscape
mode. When reading, you can change the screen orientation by tapping on the Menu button
and selecting Portrait or Landscape Mode. Note that the option displayed depends upon the
current orientation of your Kindle.

Portrait Mode

[image]
[image]

Kindle User’s Guide 8
Chapter 1
Getting Started
Landscape Mode
If you prefer, you can change pages by swiping the screen with your finger. To go to the next
page, swipe your finger from the right to the left across the screen. To go to the previous page,
swipe your finger from the left to the right across the screen.

Toolbars
EasyReach also lets you tap the top of the screen to display a toolbar. Toolbar options vary
depending on what you are viewing.

Standard toolbar
Home: Tap to return to the Home screen, where you'll find a list of books and other content
stored on your Kindle.

Back: Tap to retrace your steps. For example, you can follow a link from a book, then tap the
Back button to return to your place in the book.

[image]
Kindle User’s Guide 9
Chapter 1
Getting Started
Screen Light: Tap to access screen light controls. There are several ways to adjust screen
brightness:
 Drag your finger along the slider until you reach the desired setting.

 Tap anywhere on the slider to select a specific setting.

 Tap the "+" sign to use a higher light setting, and tap the "-" sign to use a lower light setting.

Press and hold the "+" sign to select the standard maximum brightness setting. Tap the Max
button to temporarily increase the screen brightness even further. Press the "-" sign to
decrease the brightness setting. Press and hold the "-" sign to choose the minimum brightness
setting.

Kindle Store: Tap to go to the Kindle Store. Your Kindle must have an active Wi-Fi or 3G
connection to use this feature.

Search: Tap to bring up the search field. To exit search, tap the X on the right side of the
search bar.

Goodreads on Kindle: Tap to connect to the Goodreads community on your Kindle to see
what your friends are reading, find book recommendations, and keep track of what you’ve
read and want to read. For more information, see Goodreads on Kindle. The Goodreads
button will not display if:
 It is not available in your country of residence or location.

 Your device is not yet registered.

Menu: Tap to display a list of options. The menus are contextual, which means they change to
offer appropriate options depending on what you're currently doing with the device. For
example, on the Home screen of a Kindle with Special Offers, menu options may include Shop
Kindle Store, View Special Offers, Kindle FreeTime, Vocabulary Builder, Experimental
Browser, Settings, List or Cover View, Create New Collection, Sync and Check for Items, and
About Collections. Note that you can view content on the Home screen using the default cover
view or by list view.

When you're reading a book, menu options may include Shop Kindle Store, Vocabulary
Builder, Settings, Notes, Portrait or Landscape Mode, About This Book, About the Author,
Sync to Furthest Page Read, Reading Progress, and Word Wise. Note that About the Author is
only available for books that support author profile.

Reading toolbar
A secondary toolbar displays when you're reading a book and tap the top of the screen.

[image]

Kindle User’s Guide 10
Chapter 1
Getting Started
Text (Aa): Tap to display font and text options for your Kindle books, including font size,
typeface, publisher font, line spacing, and margins.

Go To: The Contents tab displays the book’s contents, including Beginning and chapter titles.

Use the Page or Location option to further navigate your book. The options displayed will
vary depending on the content you're reading. Tap the Notes tab to access your notes and
highlights. You can also view Popular highlights and Public notes by selecting the
corresponding options under the Notes tab.

X-Ray: The X-Ray feature lets you explore the “bones” of the book with a single tap. For
example, you can see all of the passages in a book that mention specific ideas, fictional
characters, historical figures, places, topics, and terms. You can also view notable clips and
images from a book in a stack of digital cards organized on a timeline, enabling you to quickly
skim through the clips and view all of the images in one place. For more information, see
X-Ray.

Share: Tap to share your thoughts with friends on Goodreads on Kindle and other social
networks.

Bookmarks: Tap to add or delete a bookmark on the current page, and view previously
added bookmarks. The Bookmark button on the toolbar changes from white to black on
bookmarked pages. A preview pane displays when you tap a bookmark in the list. To go to the
selected location, tap the preview pane. To exit the bookmark feature, tap outside of the
bookmark dropdown.

Reading Navigation toolbar
When reading, swipe up from the bottom of the page to display the reading navigation
toolbar.

[image]

Kindle User’s Guide 11
Chapter 1
Getting Started
Use this toolbar to navigate a book and preview a new page or location in the book. For more
information, see Navigating a book.

Periodical toolbar
When you're reading a periodical, the toolbars are configured specifically for periodicals. To
display the toolbar, tap the top of the screen.

Periodical Home: Tap to display highlights of this issue.

Sections and Articles: Tap to go to the hierarchical list of sections and articles in a
newspaper or magazine. This option is not available in blogs.

A secondary toolbar is available when you're reading a periodical and are on the article detail
page. Options include:
Text (Aa): Tap to display font and text options for your periodicals, including font size,
typeface, line spacing, and margins.

Clip This Article: Tap to clip an entire periodical article to the My Clippings file. The My
Clippings file is located on your Home screen and stores your notes, bookmarks, highlights,
and clipped articles.

Status indicators
At the top of the Home screen, you'll see indicators that inform you about the status of your
Kindle Paperwhite. To view these indicators within a book or document, tap the top of the
screen to display the toolbars.

Wireless status indicators
The Amazon Whispernet service wirelessly delivers content to your Kindle whenever and
wherever you want it. Your Kindle can connect to Whispernet via its built-in Wi-Fi capability;
some models also include free 3G wireless connectivity to Whispernet. The more bars on the
Wi-Fi or 3G status indicator that are filled, the stronger the signal.

Your Kindle is connected to Whispernet using Wi-Fi.

Kindle User’s Guide 12
Chapter 1
Getting Started
Your Kindle is connected to Whispernet using a 3G cellular network. Alternatively, you may
see an icon for an EDGE or GPRS network next to the signal-strength bars. (Applies only to
Kindle 3G.)

Your Kindle is in Airplane Mode and you have no wireless connectivity.

Battery status indicator
The Kindle battery indicator shows the various states of the battery as it discharges. When
your Kindle is charging, a lightning bolt appears on the battery icon. Note that a weak
wireless signal can increase power consumption.

Activity indicator
This indicator appears in the top left corner of your Kindle screen when it is scanning or
connecting to a network, busy downloading new content, syncing and checking for new items,
searching for an item, opening a large PDF file, or loading a web page.

Parental Controls indicator
This indicator appears when Parental Controls are enabled, either because you have turned
on specific restrictions or because a Kindle FreeTime profile is active. For more information,
see Parental Controls.

Setting up your Kindle Paperwhite
If you're reading this guide, you've probably completed the Kindle setup process, which
includes selecting your device language, connecting to a wireless network, registering your
Kindle to your Amazon account, and optionally linking your Kindle to your social network
accounts. If you haven't done these steps yet, go to the Home screen now, select Set Up Your
Kindle, and follow the onscreen prompts. If you have difficulty connecting to your wireless
network, please contact your Network Administrator or the individual responsible for
maintaining the network you are trying to access. Once you have completed the setup
process, Set Up Your Kindle will no longer appear on your Home screen.

To register a Kindle that has been previously registered, tap the Menu button and select
Settings. On the Settings page, select Registration and Household, then Register/Deregister
Device. If you have enabled Sign in Approval, you will need to enter your passcode followed
by the security code sent to your phone when you register the device.

Network connectivity
Books, magazines, and other materials are delivered directly to your Kindle via its built-in
network connectivity. If your Kindle offers both Wi-Fi and 3G connectivity, use Wi-Fi
whenever possible for faster downloads. You can connect to a Wi-Fi network at home or at
hotspots around the world.

To view available Wi-Fi networks, tap the Menu button and select Settings. On the Settings
page, select Wi-Fi Networks and the name of the network you want to use. If you see a lock
symbol next to the network name, it requires a password. Tap the Rescan button to recheck
Kindle User’s Guide 13
Chapter 1
Getting Started
for available Wi-Fi networks. Please note that your Kindle does not support connecting to ad
hoc (or peer-to-peer) Wi-Fi networks.

Your Kindle will recognize Wi-Fi networks with a WPS compatible router. To connect via
WPS, from your Kindle select the wireless network you want to use. Next, press the WPS
button on your router, then select the WPS button on your Kindle during the Wi-Fi setup
process. Once you have successfully connected to a network, the Wi-Fi status indicator will
display the network's signal strength.

Kindle Paperwhite 3G models use the same technology as cell phones, so they are dependent
on cellular coverage areas. By default, a 3G device will automatically connect to a 3G network.

If there isn't sufficient 3G signal strength, it will connect to a slower GPRS or EDGE network.

Your Kindle automatically turns off 3G when you connect using Wi-Fi. If you disconnect from
a Wi-Fi network or move out of Wi-Fi range, your Kindle will automatically switch back to 3G.

To turn wireless off, tap the Menu button and select Settings, then toggle Airplane Mode on.

Any periodical downloads or other pending updates that require a wireless connection will
occur the next time you turn it back on. Turning on Airplane Mode disables both 3G and Wi-Fi
connections.

Special Offers and Sponsored Screensavers
For Kindle with Special Offers devices, you will receive Special Offers and Sponsored
Screensavers that display only on the Home screen or screensaver—not within a book. Note
that Special Offers and Sponsored Screensavers are not available in all countries.

Screensaver
When your device is sleeping, a Special Offer will be displayed on your screensaver. To see
more details on the offer, wake up your Kindle, then tap the "Tap for Details" area. To unlock
your Kindle without viewing offer details, swipe your finger to unlock. Special Offers and
Sponsored Screensavers are updated regularly when your Kindle is connected to a network.

Special Offer banners
Special Offer banners are displayed at the bottom of the Home screen. To view additional
details, tap the banner.

To view all available Special Offers:
1. Tap the Home button, then tap the Menu button.

## 2. Tap View Special Offers.

3. Tap on any available offer to view details about it.

Note that if you buy a Special Offer when your Kindle is offline, your order will not be
processed immediately. The purchase will be queued and the transaction will be
automatically completed the next time you connect to a network. To manage Special Offers,
tap the Menu button and select Settings. On the Settings page, select Device Options,
Personalize your Kindle, Advanced Options, then Special Offers.

Kindle User’s Guide 14
Chapter 2
Acquiring & Managing Kindle Content
Chapter 2
Acquiring & Managing Kindle Content
Shop the Kindle Store anytime, anywhere
The Kindle Store offers a wide selection of Kindle books, Kindle Singles, newspapers,
magazines, and blogs. To access the store, tap the top of the screen to display the toolbars,
then tap the Shopping Cart button. You can also select Shop Kindle Store from some menus.

To navigate within the Kindle Store, simply tap on any area of interest, then swipe left and
right or up and down to move around pages and lists. You can search for a title, browse by
category, check out the latest best sellers, or view recommendations personalized just for
you. The Kindle Store lets you see details about titles, read customer reviews, and even
download book samples.

When you're ready to make a purchase, the Kindle Store securely uses your Amazon 1-Click
payment method. After you order, the Amazon Whispernet service delivers the item directly
to your Kindle via your wireless connection. Books are downloaded to your Kindle
immediately, generally in less than 60 seconds. The download progress will display below the
book’s cover or title on the Home screen indicating the download status. A New banner on the
book indicates when the book is ready to be opened. Newspapers, magazines, and blogs are
sent to your device as soon as they're published—often even before they're available in print.

If your Kindle is in Airplane Mode when a new issue of a periodical becomes available, the
issue will be delivered automatically the next time you have a wireless connection.

Whispersync synchronizes your Kindle device so that purchases and downloaded book
samples within Kindle apps or other Kindle devices registered to your account are always
available to you. This enables you to read a few pages using the Kindle application on your
iPhone, iPad, or Android device and then pick up right where you left off when you return to
your Kindle device. For more information, see Reading Kindle content on other devices.

Kindle Unlimited is an optional monthly subscription that enables you to read as much as you
want on any device, and choose from over 700,000 titles and thousands of audiobooks. You
can freely explore new authors, books, and genres from mysteries and romance to sci-fi and
more. To learn more, visit the Kindle Store.

Recommended content
When in cover view, your Kindle Home screen displays recommended content from the
Kindle Store, such as Editors’ Picks. In addition, you will see Goodreads Want to Read shelf
content if you have shelved enough qualified books to your Goodreads on Kindle Want to
Read shelf. Tapping an item will direct you to the Kindle Store, where you can view additional
details, read customer reviews, and complete purchases. Swipe or tap to view additional
content. To hide recommended content, tap the Menu button and select Settings. On the
Settings page, select Device Options, Personalize your Kindle, Advanced Options, then Cover
View Recommendations.

Kindle User’s Guide 15
Chapter 2
Acquiring & Managing Kindle Content
Device and Cloud storage
Content that is purchased from the Kindle Store is securely stored and available in the Cloud.

This includes copies of all your books, along with recent issues of newspapers and magazines.

To view your Cloud content, tap Cloud in the top left of the Home screen.

Cloud tips:
 If you wish to download content that you have in the Cloud, tap Cloud on the Home screen,
then tap on the item(s) you want to download to your Kindle. You can cancel a download by
tapping on the item's title.

 Cloud items that have been downloaded to your Kindle display a check mark on the upper
right corner of the cover image when in cover view and on the right side of the screen when
in list view.

 Once you have downloaded an item, you can either open it from the Home screen or directly
from the Cloud.

 Your personal documents are saved in the Cloud if they have been emailed to your Kindle and
if you have enabled Personal Document Archiving on the Manage Your Content and Devices
page.

To view content stored on your Kindle, tap On Device. If you are preparing to go offline, tap
Cloud and download to your Kindle any content that you want to have available when offline.

The Manage Your Content and Devices page, accessible from
http://www.amazon.com/devicesupport, offers a handy way to view and manage your Kindle
content, settings, and account using a web browser.

Removing items from your Kindle
To free up space on your Kindle, you can remove items by pressing and holding the item's
name or cover on the Home screen. When the dialog box displays, tap Remove from Device.

Your content will remain securely stored in the Cloud for download at a later time. Note that
files transferred to your Kindle using the USB cable will be permanently deleted when you
remove them, because they are not stored in the Cloud.

Your personal documents are saved in the Cloud if they have been emailed to your Kindle and
if you have enabled Personal Document Archiving on the Manage Your Content and Devices
page, accessible from http://www.amazon.com/devicesupport. For information on personal
document management, see Carrying and reading personal documents.

Periodicals
Newspapers and magazines are stored in folders by periodical name. When you open the
folder, you can select either Cloud or On Device view, and download and open periodicals.

Issues that are more than eight issues old will be automatically deleted from your device to
free up space for new content. Newspapers that are more than 14 issues old, and magazines
that are more than 40 issues old, will be automatically deleted from the Cloud. "Expiring" next
to an issue indicates that it will be deleted soon. Press and hold on a periodical folder to view
the following options: Open Latest Issue, View Back Issues, and Remove All Back Issues.

Kindle User’s Guide 16
Chapter 2
Acquiring & Managing Kindle Content
You can view more options when you press and hold on a single issue. Options include Go To
First Page, Go To Sections & Articles, Search This Issue, Keep This Issue, View Notes & Marks,
View Back Issues, and Delete This Issue.

There are two ways to keep a copy of an issue on your device:
 On the Home screen, tap On Device and then press and hold on the name or cover of the issue
you wish to keep. Select Keep This Issue from the options.

 From within the issue, tap the Menu button and select Keep This Issue.

You can access all of your back issues, regardless of age, on the Manage Your Content and
Devices page, accessible from http://www.amazon.com/devicesupport.

Managing your Kindle Library
Your Kindle Paperwhite can store thousands of books, personal documents, newspapers,
blogs, and magazines, which are referred to collectively as "content" throughout this guide.

To display a list of content on your Kindle Paperwhite, tap the Home button, then the On
Device option.

To view how much free space your Kindle has available for storing content:
1. Tap the Menu button and select Settings.

2. On the Settings page, tap the Menu button, then Device Info.

You can view content on the Home screen using the default cover view or by the traditional
list view. To change the appearance of the Home screen, tap the Menu button and select List
or Cover View.

By default, your content is sorted by Recent, meaning that new items and the content you're
currently reading are at the top. To change the sort option, on the Home screen tap the name
of the existing sort order, located under the toolbar. You can also sort items that you have
stored in the Cloud.

To filter your content by type, on the Home screen tap All Items, located under the toolbar.

Filtering options include:
 All Items
 Books
 Periodicals
 Docs
 Collections
If you have set up a household and enabled sharing, two new filtering options will appear
under Books:
 My Books
 Shared Books
To view just your books, select the My Books filter option. To view just the books that the
other adult in your household has shared, select the Shared Books filter option.

You can also filter items that you have stored in the Cloud.

To jump to a specific title or page, go to the Home screen and tap the page number control.

For example, 1/2 indicates you are on page 1 and have 2 pages of content on your Kindle.

When the dialog box displays, enter the page number you want to go to or the first letter of
the title or author (depending upon your current sort option).

Kindle User’s Guide 17
Chapter 2
Acquiring & Managing Kindle Content
To view more information about an item and access a menu of applicable options, go to the
Home screen and press and hold on the item’s cover (or name if using list view). Menu
options vary, but may include Add to FreeTime Library, Add to Collection, Go To..., Search
This Book, View Bookmarks, Remove from Device, View on Goodreads, and Add to Goodreads
Shelf. Note that you must be signed in to Goodreads on your Kindle to see Add to Goodreads
Shelf.

Cloud Collections
Cloud Collections enable you to organize the content on your Kindle Paperwhite into
customized categories that are stored in the Cloud. Your collections are synced between other
devices and reading apps that are registered to the same Amazon account and that support
Cloud Collections. You can add as many items as you like to each collection, including books,
and personal documents. Items can also be added to more than one collection. For
information on devices and apps that support Cloud Collections, go to
http://www.amazon.com/devicesupport.

To create a new collection:
1. On the Home screen, tap the Menu button.

## 2. Select Create New Collection.

3. Use the keyboard to type a name for the collection, then tap OK. A list of the items on your
Kindle that can be added to a collection displays.

4. Tap the checkbox next to an item's title to add it to the collection, then tap Done when
finished.

You can add or remove items at a later time by tapping on the Menu button when in a
collection and selecting Add/Remove Items. Other options include Rename Collection, Delete
Collection, and visibility settings. To exit a collection, tap the Home or Back button.

To filter the content on your Home screen by collection, tap All Items or the currently selected
filter, and select Collections.

Collections downloaded to the device appear in your All Items, Books, Periodicals, and Docs
views. To download a collection, just press and hold on a collection cover or collection title
and tap Add to Device. Note that this setting is device-specific and will not be saved when you
deregister your Kindle. To remove a collection from your device, press and hold on a
collection cover or collection title, and then tap Remove from Device.

Cloud Collections tips:
 Deleting a collection that was created on a device or in a reading app that supports Cloud
Collections, such as your Kindle, will delete it from the Cloud and other devices or reading
apps that support Cloud Collections and are registered to the same Amazon account.

 Deleting a collection from your Kindle does not remove the content stored on your device or
in the Cloud. Items previously placed into the collection that are stored on your Kindle will
appear on the Home screen and in the Cloud after the collection is deleted.

Kindle User’s Guide 18
Chapter 3
Reading Kindle Documents
Chapter 3
Reading Kindle Documents
Understanding Kindle display technology
Your Kindle uses a high-resolution display technology called electronic paper. The display is
reflective, which means you can read it clearly even in bright sunlight. Electronic paper uses
ink just like books and newspapers, but it displays the ink particles electronically.

On occasion, your screen may seem to flash. This is part of the process of updating the e-
reader display. By default, your Kindle features fast, smooth page turns, minimizing the
number of flashes. To refresh the page with every page turn, tap the Menu button and select
Settings. On the Settings page, select Reading Options and use the Page Refresh setting to set
your preference. For manga refresh settings, tap the Menu button when reading a manga
book and select the Page Refresh On/Off setting.

Customizing your text display
Your Kindle provides a quick way to adjust the appearance of books and periodicals. To
access those settings when reading, tap the top of the screen to bring up the toolbars, then tap
the Text button (Aa). A dialog box will appear that lets you change the font size, typeface, line
spacing, and margins of the content on the Kindle screen. The Publisher Font option is
available on select books that include the ability to view the fonts embedded by the publisher.

You may be prompted to update your Kindle if new fonts are available.

Comic and manga books
Comic and manga books come alive with Kindle Panel View. To enter Kindle Panel View,
double tap the screen. To navigate through the panels, swipe your finger across the screen or
tap the sides of the screen. To exit Kindle Panel View, double tap the screen again. For manga
refresh settings, tap the Menu item when reading a manga book and select the Page Refresh
On/Off setting.

Children's books
Some Kindle children's books feature Kindle Text Pop-Up for reading text over images. You
can navigate between Text Pop-Up sections by swiping your finger across the screen or
tapping the sides of the screen. Select children's books will automatically open in this view.

To exit Text Pop-Up and return to normal reading, double tap the screen.

Zooming images
You can increase the size of an image in a Kindle book for easier viewing. Press and hold your
finger on the image and then release to display a magnifying-glass icon, then tap on the icon.

Kindle User’s Guide 19
Chapter 3
Reading Kindle Documents
To return the image to normal size, tap on the image again. For select Kindle books, you can
zoom in further by placing two fingers close together on the center of the screen and moving
them apart. To zoom out, place two fingers slightly apart on the screen and pinch them
together. While zoomed, drag your finger across the image to move to the area of interest. To
return to reading, tap the X in the top right corner of the image.

Panning and zooming tables
Enhanced viewing is available for tables that are interactive, enabling you to both pan and
zoom. Tap on the table to display the panning and magnifying-glass icons.

To pan, tap the panning icon and then drag your finger across the screen in the direction you
want to pan. You can select text in the table by pressing and holding on the text, then dragging
your finger across the screen to select it. To edit the range of your highlight after you have
selected it, press and hold on the handle at the start or end of the highlight and drag your
finger across the screen to the desired location. Handles only appear when you have selected
two or more words for most device languages. A dialog box will appear with options to
highlight the text, add a note, share, and more. To exit panning mode, tap the Done button.

To zoom, tap the magnifying-glass icon. To zoom in further, place two fingers close together
on the center of the screen and move them apart. To zoom out, place two fingers slightly apart
on the screen and pinch them together. While zoomed, drag your finger across the table to
move to the area of interest. To return to reading, tap the X in the top right corner of the table.

Interacting with your documents
Your Kindle gives you access to features that are not available with printed materials, such as
instantly viewing word definitions, easy access to footnotes, and end of book actions. Just as
with a traditional book, you can also highlight favorite passages, add notes, and create
bookmarks.

About This Book
Before starting a new book, you can get valuable information and perform actions to improve
your reading experience. Options vary by book, but may include:
 Typical time to read
 Mark as currently reading on Goodreads
 About the author
 Mentioned in this book
 Customers who read this book also bought
 Manage this feature in Settings
 Send us feedback
To enable or disable this feature, tap the Menu button and select Settings. On the Settings
page, select Reading Options, Notes & About This Book, then About This Book.

Dictionary
Your Kindle includes one or more dictionaries for each supported language. After you have
successfully registered your Kindle, all of your dictionaries will be available in the
Kindle User’s Guide 20
Chapter 3
Reading Kindle Documents
Dictionaries collection either on the Home screen or in the Cloud. Available dictionaries will
differ depending on the language you select.

To change your default dictionary:
1. On the Home screen or when reading, tap the Menu button and select Settings.

2. On the Settings page, select Device Options and then Language and Dictionaries.

## 3. Select the Dictionaries option.

4. The currently selected dictionary displays below the dictionary language. An arrow to the
right of the language indicates that there are multiple dictionary options for that language.

Tap the dictionary language to view all of the available dictionaries for that language.

5. Use the radio buttons to select the dictionary that you want to use, then tap the OK button.

To look up the definition of a word while reading, press and hold to select the word. A dialog
box displays with the definition of the word. You can change your dictionary by tapping on
the name of the current dictionary in the dialog box. An option to select a new dictionary will
display.

The Smart Lookup feature integrates a full dictionary with X-Ray and Wikipedia so you can
access definitions, characters, settings, and more without leaving your page. If the selected
word is also an X-Ray topic, Smart Lookup will display the X-Ray tab. For more information,
see X-Ray.

Search
To perform a search, tap the Search button to display the search field and onscreen
keyboard. When you search from the Home screen, the default search is everywhere,
including the results from your library, Kindle Store, Goodreads, Text in Books, Dictionary,
and Wikipedia. To initiate a full search, tap the Return key on the keyboard or click on the
Search Everywhere option in the dropdown menu that appears as you type in search criteria.

To search within a book or document when reading, tap the top of the screen to bring up the
toolbars, then tap the Search button and enter the text you want to search for.

Search tips:
 For results from All Items, your Kindle will actively display title/author matches in a
dropdown menu as you type in the search criteria. To go directly to an item, tap the match in
the dropdown. If a match is found for a book, it will take you to the most recent page read or
download the book if you have it in the Cloud.

 For results from the Kindle Store, your Kindle will actively display the suggestions in a
dropdown menu as you type in the search criteria. When you tap the match in the dropdown,
it shows the results in the Kindle Store. Tap the Search Everywhere button to broaden your
search.

 From the Experimental Web Browser, tap to the left of the address field to display all of the
search filter options: Web Address, Google, and Kindle Search.

 Searching will be limited if Parental Controls are enabled, and will not include results from
the Kindle Store, Goodreads, and Wikipedia.

 Tap the Clear History link to delete your search history.

 When searching while using Goodreads on Kindle, the default search is by title and author
within the Goodreads catalog. To add a book to your Goodreads shelves, tap Want to Read or
the Shelf icon next to the book in search results. Tap on a book cover to read reviews
and view details in the Kindle Store. For more information, see Goodreads on Kindle.

Kindle User’s Guide 21
Chapter 3
Reading Kindle Documents
To exit search, tap the X on the right side of the search bar.

Notes and highlights
You can add notes and highlights by pressing and holding on text, then dragging your finger
across the screen to select it. Highlighting tips:
 To highlight to the next page, drag your finger to the bottom right corner of the screen and
the page will turn. You can highlight across multiple pages by continuing to drag your finger
to the bottom right corner of the screen.

 To highlight to the previous page, drag your finger to the top left corner of the screen and the
page will turn. You can highlight across multiple pages by continuing to drag your finger to
the top left corner of the screen.

 To edit the range of your highlight after you have selected it, press and hold on the handle at
the start or end of the highlight and drag your finger across the screen to the desired location.

Handles only appear when you have selected two or more words for most device languages.

If you select a single word and want to add a note, tap More and select Add Note. Additional
options can include highlighting the selected text, sharing with friends on Goodreads on
Kindle and other social networks, searching Wikipedia, translating the selected word,
searching, or reporting an error with the content.

If you select a sentence or multiple words, a dialog box will appear with options to Add Note,
Share, Highlight, and More. Tap More for other options, including Wikipedia, Translation, and
Report Content Error.

Notes will appear as superscripted numbers within the text. To view a note the next time you
visit that page, simply tap on the number. You can view all of your notes and highlights by
tapping the Go To option on the secondary toolbar when reading and tapping the Notes tab.

The notes and highlights closest to your current reading location will display first in the list.

You can also view notes by tapping the Menu button and selecting Notes.

If several other Kindle users have highlighted a particular passage in the book you are
reading, you will see that passage underlined. To turn off these highlights, tap the Menu
button and select Settings. On the Settings page, select Reading Options, Notes & About This
Book, and change the Popular Highlights setting. You can also display notes and highlights
from people that you follow on https://kindle.amazon.com. To turn off this option, tap the
Menu button and select Settings. On the Settings page, select Reading Options, Notes & About
This Book, and change the Public Notes setting. The Popular Highlights and Public Notes
features are not supported in all countries.

Notes and highlights are added to a file on the Home screen called My Clippings. When
Whispersync for Books is set to Enabled, these items are stored in the Cloud for you so they
won't be lost. To manage the Whispersync for Books setting, tap the Menu button and select
Settings. On the Settings page, select Device Options, Personalize your Kindle, Advanced
Options, then Whispersync for Books.

Bookmarks
Amazon's Whispersync technology automatically saves your place in whatever content you
are reading. To bookmark a page, tap the Bookmark button on the reading toolbar and tap the
plus sign next to the location or page information. A black bookmark will appear in the top
right corner of the page. The Bookmark button on the toolbar changes from white to black on
bookmarked pages.

Kindle User’s Guide 22
Chapter 3
Reading Kindle Documents
Bookmark tips:
 You can view a list of all of your bookmarks within a book by tapping the Bookmark button on
the reading toolbar or by tapping the top right corner of the page.

 To preview a bookmarked page or location, tap any bookmark in the list. To go to the selected
location, tap inside the preview pane. To remain on the current page and exit the bookmark
feature, tap outside of the preview pane.

 To delete a bookmark, tap the Bookmark button on the reading toolbar, find the bookmark
you want to delete in the list, tap the bookmark to select it, then tap the X next to it.

 Bookmarks are added to a file on the Home screen called My Clippings. When Whispersync
for Books is set to Enabled, these items are stored in the Cloud for you so they won't be lost.

Footnotes
To quickly preview a footnote without losing your place in the book, tap the footnote. To go to
the selected footnote location, scroll to the bottom of the footnote preview pane and tap Go to
Footnotes. To return to your original location, tap the X on the preview pane. Note that not all
books support the Footnotes feature.

Before you go...

The Before you go... dialog appears when you reach the end of a book, or after you swipe past
the final page of a book, and enables you to rate the book using stars and purchase the next
book in a series.

X-Ray
The X-Ray feature lets you explore the "Bones of the Book" with a single tap, enabling you to
see all of the passages in a book that mention specific ideas, fictional characters, historical
figures, places, topics, and terms. X-Ray also extracts notable clips and images from a book
and presents them in a stack of digital cards organized on a timeline, enabling you to quickly
skim through the clips and view all of the images in one place.

When you're reading a book, press and hold on a character’s name or a place mentioned in
the book to view the corresponding X-Ray topic. You can also tap the top of the screen to
display the secondary reading toolbar, and then tap the X-Ray button. If X-Ray is not available
for a book, the button will be disabled. X-Ray will scan your entire book and a dialog box will
display. Tap the People, Terms, or Image links to view the results. Tap the timeline to view
notable clips in other parts of the book. Additional excerpts beyond your furthest page read
are hidden until you tap to show all excerpts. Note that X-Ray is not available for all Kindle
books or in all countries. Look for X-Ray Enabled in the Kindle Store description of the book
to find out if a book has X-Ray.

Word Wise
Word Wise, available on many popular English-language titles, makes it easier for readers
learning English and kids reading their first chapter books to understand challenging books
more quickly. When Word Wise is on for an enabled title, short and simple definitions
automatically display above difficult words so you can keep reading without the need to look
words up. To learn more or see the various meanings the same word can have in a different
Kindle User’s Guide 23
Chapter 3
Reading Kindle Documents
context, tap the word to display a card with definitions, synonyms, and more. Tap Word Wise
in the bottom right corner of the screen and use the slider to adjust the number of hints you
see. To turn on Word Wise, tap the Menu button and select Word Wise.

You may also see multiple-choice hints for words with more than one possible meaning when
we’re not quite sure which is the right one. For those words, we show you our best guess
above the word. When you tap the hint, a list of all possible meanings of the word display and
you can help let us know which one is most helpful in the given sentence. To turn off Show
Multiple-Choice Hints, tap the Menu button and select Word Wise, then disable Show
Multiple-Choice Hints.

Vocabulary Builder
Words you look up in the dictionary are automatically added to Vocabulary Builder. To view
your word list and quiz yourself with flashcards, tap the Vocabulary Builder item on the
Home screen, or select it from the menu on the Home screen or while reading a book.

To view your word list, tap Words in the top left of the screen. Tap a specific word to view its
definition and a usage example. To view your words by book, tap the Books link.

Each time you tap the Flashcards option, Vocabulary Builder selects a set of words from the
current list and displays them as Flashcards. To view a word’s definition, tap "See Definition"
in the top left corner of the Flashcard. Tap the Learning link on the Vocabulary Builder main
screen to see how many words you are currently learning and how many you have already
mastered.

To turn Vocabulary Builder off, press and hold on the Vocabulary Builder item on the Home
screen and select Turn Off Vocabulary Builder. You can also turn it off or on by tapping Menu
and selecting Settings. On the Settings page, select Reading Options, Language Learning, then
Vocabulary Builder. Note that words you look up are not added to Vocabulary Builder when it
is off.

Kindle FreeTime
Kindle FreeTime lets you create a personalized experience for up to four children, giving you
complete control over what content each child can access. Kids earn achievements that help
them keep track of their personal reading accomplishments.

Kindle FreeTime automatically blocks access to the Kindle Store, the Experimental Web
Browser, Goodreads, and Wikipedia. Children can only read books that you have added to
their library.

Kindle FreeTime Unlimited is an optional monthly subscription that offers thousands of
books, apps, movies, and TV shows for children ages three- to ten-years-old. Tap the
Characters button on the toolbar to view content categories. Apps, Movies, and TV shows are
not available on your Kindle E-reader, but can accessed at no additional charge on your Fire
tablet or Amazon Fire TV. Not all books included in Kindle FreeTime Unlimited are supported
on your Kindle E-Reader due to publisher exclusions, but can be viewed on your Fire tablet.

Setting up Kindle FreeTime
Kindle User’s Guide 24
Chapter 3
Reading Kindle Documents
Tap the Kindle FreeTime item on the Home screen to get started. You will be prompted to set
a Parental Controls password if you do not already have one. To create a profile for your
child, enter your child’s first name, date of birth, and gender. A Kindle FreeTime Unlimited
page displays.

Next, a list of the titles in your Kindle Library displays. Tap the checkbox next to an item’s title
to add it to your child’s Kindle FreeTime library, then tap OK. To add or remove books from
your child’s reading list later, tap the profile icon next to your child’s name on the Kindle
FreeTime main screen, then select Library.

Set Access to Achievements to On to enable your child to view earned achievements. Use the
Daily Reading Goal option to specify the number of minutes your child should read each day.

Once you have completed the Kindle FreeTime profile setup process, simply tap the Kindle
FreeTime item on the Home screen to access profiles. You can create up to four profiles. To
manage a profile later, tap the profile icon next to a child’s name. Options include
Progress, Library, Edit, Delete, and Subscription. Choosing the Delete option will permanently
delete the profile, including that child's reading statistics and any achievements they may
have earned.

To exit Kindle FreeTime, tap the Menu button on the Home screen and select Exit FreeTime.

You will be prompted to enter your Parental Controls password. To access Kindle FreeTime
or turn it back on, tap the Menu button on the Home screen and select Kindle FreeTime. To
start a session for your child, open Kindle FreeTime and tap on your child’s name.

Using Kindle FreeTime
To view your child’s progress, tap the profile icon next to their name, then select
Progress. Tap the Books link in the top left of the screen to view the percentage of each book
read, total reading time, average reading time per session, and the number of words that your
child looked up in the dictionary.

Tap the Activity link in the top left corner to view the number of achievements, progress
towards the daily reading goal, pages read, hours read, books finished, and the total number
of looked-up words. Use the arrows to view progress within the last week. Tap the date to
view achievements by day, month, and total. Tap the Achievements link in the top left corner
to see which achievements your child has earned.

Your child will see a customized Home screen, including the books you selected and a new
Progress button on the toolbar. Tapping the Progress button displays the same Book and
Activity links that you see, and the Achievements link if you elected to turn on the Access to
Achievements option.

Managing your Amazon household
You can now set up a household with another adult in your family, enabling both of you to
jointly manage up to four Kindle FreeTime child profiles. Family Library lets you share books
with each other across Amazon devices and Kindle apps. This will not impact your
annotations, most recent page read, and last page read in books. Please read this section prior
to creating a household to familiarize yourself with the process and terms.

Kindle User’s Guide 25
Chapter 3
Reading Kindle Documents
To add a second adult to your household:
1. Tap the Menu button and select Settings. On the Settings page, select Registration and
Household, then Household and Family Library.

2. Tap Add a New Person, then Add Adult. You will be prompted to pass your Kindle to the adult
you would like to add to your household.

3. The second adult must enter a unique Amazon account ID and password. If they do not have
one, they can follow the link to create one.

4. The second adult will be given the opportunity to enable sharing. They can choose if they
want to share all of their purchased books or just individual books with you. By choosing to
enable sharing, they are authorizing you to use credit cards associated with their Amazon
account for purchases on Amazon.

5. The second adult will be prompted to pass your Kindle back to you.

6. You will also be given the opportunity to enable sharing. You can choose if you want to share
all of your purchased books or just individual books with the second adult. By choosing to
enable sharing, you are authorizing the second adult to use credit cards associated with your
Amazon account for purchases on Amazon.

To add a child to your household:
1. You will be prompted to set a Parental Controls password if you do not already have one.

2. To create a profile for your child, enter your child’s first name, date of birth, and gender. This
will create a Kindle FreeTime profile for your child. For more information on setting up and
managing this profile, see Kindle FreeTime.

To edit attributes associated with people in your household, tap the Menu button and select
Settings. On the Settings page, select Registration and Household, then Household and Family
Library. Tap the name of the individual to:
 Manage Family Library
 Manage Share All Books
 Select devices that show shared content
 Manage payment methods
 Remove that individual from the household on all devices
Note that leaving a household will result in both adults not being allowed to join or start a
household for 180 days, and the household cannot have another adult added for 180 days.

Your digital content and payment methods will no longer be shared with the other adult in
the household. You will also no longer be able to administer child accounts that are part of the
household. You can manage individual books for sharing on the Manage Your Content and
Devices page, accessible from http://www.amazon.com/devicesupport.

Goodreads on Kindle
Connect to the world's largest community of readers with Goodreads on Kindle, where you
can find book recommendations, keep track of what you've read and want to read, and see
what your friends are reading. Tap the Goodreads button on the toolbar to get started. You
will be prompted to sign in to Goodreads or create a new account if you did not do so when
setting up your Kindle.

Kindle User’s Guide 26
Chapter 3
Reading Kindle Documents
When you log in with an existing Goodreads account, your account data will sync with your
Kindle, including your friend list and your Want to Read, Currently Reading, and Read
shelves.

When you create a new account, you will have the opportunity to add Facebook friends and
choose Readers to Follow. If you connect using your Facebook account, any Facebook friends
who are also on Goodreads will be automatically added to your Goodreads friend list. The
more friends and readers you follow, the more book recommendations you will see in your
Updates.

Keep track of what you're reading by adding books to your Goodreads shelves. When setting
up your account, you will be directed to a list of your Amazon book purchases, both digital
and physical. You can rate books you've read from one to five stars. Rating a book adds it to
your Read shelf. You can also tap the Shelf icon to shelve the book as Currently Reading
or Want to Read. Shelved and rated books are publicly visible on your Goodreads profile. You
can always remove a shelved book later by tapping the Shelf icon and selecting Remove
from Shelf.

You can also add a book to your Goodreads shelves from the Home screen of your Kindle.

Press and hold on the book's cover (or name if using list view) and select Add to Goodreads
Shelf. Then from the Select Goodreads Shelf pane, you can shelve the book as Read, Currently
Reading, or Want to Read.

Goodreads on Kindle has three tabs located in the top corner:
Updates: View recent updates from friends and readers you follow, including book reviews
and what they're currently reading. You can like and comment on any review. You can also
rate and shelve books in your Updates feed. Tap on a book cover to read more reviews. Tap
on a reader's name to view their Goodreads profile and more books on their shelves.

My Shelves: View all books on your shelves. You can filter by shelf type (Read, Currently
Reading, and Want to Read), move books to different shelves, and add Amazon books to your
shelves.

Friends: View all readers in your Goodreads network. You can filter by friends, readers you
follow, and readers following you. You can also select Find Readers to Follow to expand your
network. Tap on a reader's name to view their Goodreads profile and books on their shelves.

There is also a profile icon that you can tap to view your Goodreads profile, including your
shelved books, friends, and recent updates.

Goodreads on Kindle tips:
 Tap Want to Read when you find a book that interests you. You can also tap the Shelf icon
to mark a book as Read, Currently Reading, or Want to Read.

 Tap stars to rate a book from one to five stars.

 Tap on a book cover to read reviews, make a 1-Click purchase for select popular titles, and
view details in the Kindle Store.

 Search for your friends, approve friend requests, and view personalized book
recommendations on http://www.goodreads.com.

You must have a Wi-Fi connection to use most Goodreads on Kindle features. Note that
Goodreads is not available in all countries.

Kindle User’s Guide 27
Chapter 3
Reading Kindle Documents
Time to Read
Your Kindle Paperwhite includes Time to Read, a feature that helps you know how long it will
take to finish a chapter or book. You can customize this feature to display location numbers,
time left in chapter, time left in book, percentage of content read, or actual page numbers.

(Not all Kindle books include page numbers.)

Because Kindle books can be read on devices with different screen sizes, locations identify
specific places in a book, just like a page number would for a print book. Location numbers
allow you to direct a friend to the exact same place in a Kindle book you are reading. Many
Kindle books also contain page numbers that correspond to the real page numbers in an
actual print book.

The Time to Read feature uses a unique algorithm to estimate the amount of time it will take
you to complete the chapter or book based on your past and current reading speed. Your
specific reading speed is stored only on your Kindle; it is not stored on Amazon servers.

When reading, select Reading Progress from the menu, then choose the option you want to
display at the bottom of the page when you read. Options may include:
 Location in book
 Page in book
 Time left in chapter
 Time left in book
 None
To hide Reading Progress, select the None option.

When you tap the top of the screen, the chapter name (if available) displays at the bottom of
the screen.

Tap the caret to access the Reading Navigation toolbar. For more information, see Navigating
a book.

On the Home screen, dots below the book title indicate how long the book is, with bold dots
showing how far you have read.

Navigating a book
There are multiple ways to quickly navigate through a book:
 Kindle Page Flip
 Go To button
Kindle Page Flip
Kindle Page Flip enables you to preview other pages in a book without leaving your current
page or losing your place. To navigate a book quickly, swipe up from the bottom of the screen
to display the Page Flip toolbar.

Kindle User’s Guide 28
Chapter 3
Reading Kindle Documents
Press, hold, and drag the circle forward or back, or tap on the progress bar to preview a new
page or location in the book. Use the arrows or swipe within the preview pane to flip through
your book page-by-page. Navigation tips:
 To skim through chapters, tap the arrows.

 To return to your original location, tap the X on the preview pane.

 To go to the selected location, tap the page you are previewing.

Go To button
You can also navigate through your book using the Go To button on the reading toolbar,
accessible by tapping the top of the screen. The Contents tab displays the book’s contents,
including Beginning, End, and Chapters. Use the Page or Location option to further navigate to
a specific page or location in your book. The options displayed will vary depending on the
content you're reading. Tap the Notes tab to access your notes and highlights.

Once you have used the progress bar or the Go To button to navigate through your book, you
can also navigate through your previous reading history. To access this history, swipe up
from the bottom of the screen to display the Reading Navigation toolbar. Options include:
 Back to Page/Loc x
 Forward to Page/Loc x
Note that this history is cleared when you exit the book.

Kindle User’s Guide 29
Chapter 4
Getting More From Your Kindle Paperwhite
Chapter 4
Getting More From Your Kindle
Paperwhite
Carrying and reading personal documents
Your Kindle makes it easy to take your personal documents with you, eliminating the need to
print them. You and your approved contacts can email documents to your Kindle. To locate
your Send-to-Kindle Email address, tap the Menu button and select Settings. On the Settings
page, select Device Options, Personalize Your Kindle, then Send-to-Kindle Email. Your emailed
personal documents will be backed up in your Kindle Library and ready to download at any
time when Personal Document Archiving is enabled. To learn more about this feature and
enable Personal Document Archiving, go to the Manage Your Content and Devices page
(accessible from http://www.amazon.com/devicesupport).

You can send Microsoft Word (DOC, DOCX), PDF, HTML, TXT, RTF, JPEG, GIF, PNG, BMP, PRC,
and MOBI files to your Kindle and read them in Kindle format. You can add notes, highlights,
and bookmarks, which are synchronized across devices along with the last page you read via
our Whispersync technology. Synchronization of notes, highlights, bookmarks, and last page
read is available only for personal documents archived in Kindle format. You can also read
documents in PDF and TXT format natively.

Reading Kindle content on other devices
You can synchronize your Kindle books with other supported devices you own and Kindle
reading applications. Amazon's Whispersync technology keeps track of the last reading
location in each book. For example, you can read a few pages using the Kindle application on
your iPhone, iPad, or Android device and then pick up right where you left off when you
return to your Kindle. For a complete list of supported devices and Device Synchronization
settings, go to http://www.amazon.com/devicesupport.

Sharing comments via social networks
The share feature enables you to share books, Kindle highlights, and comments with friends
via social networks, including Goodreads on Kindle. To link your Kindle to your social
network accounts and enable sharing, tap the Menu button and select Settings. On the
Settings page, select Reading Options, then Social Networks.

Once you have set up the sharing feature, from within a book you can select Share from the
secondary toolbar and enter a message and share it with your social network. To access the
sharing feature when you select text, press and hold on text, then drag your finger across the
screen to select it. If you select a sentence or multiple words, a dialog box will appear with an
option to Share. If you select a single word, a definition of the word displays and options
include Search and More. Tap the More button to share the selected text.

Kindle User’s Guide 30
Chapter 4
Getting More From Your Kindle Paperwhite
Using your Kindle with your computer
Your Kindle uses Amazon Whispernet to deliver books, periodicals, personal documents,
Kindle Singles, and blogs to your Kindle without the need for a computer.

When you first connect the Kindle to a computer's USB port, it will appear as an external
storage drive or volume on the computer's desktop. You'll see a directory or folder called
"documents." You can add Kindle-compatible files to this directory, and you can copy, move,
or delete the files that are already there. See the Kindle Support website
(http://www.amazon.com/devicesupport) for more information on supported file types.

Your Kindle is not usable as a reading device while in USB drive mode. To read a book while
charging the battery, you must eject the Kindle from your computer's desktop.

Using the Experimental Web Browser
Your Kindle includes an experimental web browser that enables you to surf the web and view
most Amazon web pages. Web Browser supports JavaScript, SSL, and cookies, but does not
support media plug-ins. You must have a Wi-Fi connection to access most websites.

To launch Web Browser, tap the Menu button, then select Experimental Browser. The first
time you access this page, you will find a list of default bookmarks for commonly used sites.

You can access these bookmarks later, by selecting Bookmarks from the Web Browser menu.

To enter a URL, tap the search field at the top of the screen. Use the onscreen keyboard to
enter the web address. A .com key is added to the keyboard when you are entering URLs. The
address field will retain the last URL you entered.

The following tips will help you get the most out of the Kindle Web Browser:
 To zoom in on a web page or image, place two fingers close together on the center of the
screen and move them apart. To zoom out, place two fingers slightly apart on the screen and
pinch them together.

 Tap links to open a web page.

 Drag your finger left/right and up/down to navigate a web page.

 Tap the Back button in the upper left corner to return to the previous page you were viewing.

 Scroll down a web page by dragging your finger up the screen.

 To enter information in a field on a web page, select the field and the onscreen keyboard will
display.

 To return to previously viewed web pages, tap the Menu button and select History.

Web Browser Menu
From within Web Browser, tap the Menu button to view other options, including Article
Mode, Bookmarks, Bookmark this Page, History, and Browser Settings. Browser Settings
include Clear History, Clear Cookies, Disable JavaScript, and Disable Images. Note that web
pages will load faster if you disable JavaScript.

When reading an article, there is also an option to switch to Article Mode which changes the
page layout and displays the article in a simple text column eliminating surrounding images
and ads.

Kindle User’s Guide 31
Chapter 4
Getting More From Your Kindle Paperwhite
Bookmarks
To bookmark a web page, tap the Menu button and select Bookmark this Page. To delete a
bookmark, tap the Menu button and select Bookmarks. Tap the Remove button at the bottom
of the page, tap to select the checkbox next to the URL(s) you want to remove, then tap the
Remove button.

Downloading files
Some websites may have books or documents that you want to download and read on your
Kindle. You will be asked to confirm if you want to download these items to your Kindle
Home screen. Supported file types for download include Kindle content (.AZW, .AZW1, .AZW2,
and .AZW3), unprotected Mobipocket books (.MOBI, .PRC), and text files (.TXT).

Kindle User’s Guide 32
Chapter 5
Settings
Chapter 5
Settings
Customizing your Kindle settings
To go to the Settings page, tap the Menu button and select Settings. Your Kindle must be
registered to view all settings. The available settings are:
Airplane Mode: Allows you to enable or disable wireless connectivity.

Wi-Fi Networks: Use this option to connect to a Wi-Fi network, display a list of available
networks, and view the name of the Wi-Fi network you are currently connected to, if any.

Registration and Household: Enables you to manage your household and displays the
Amazon account name to which your Kindle is registered. Use this option to register and
deregister your Kindle.

Household and Family Library: Add individuals to your household to share content.

For more information, see Managing your Amazon household. This feature is not
available in all countries.

Register/Deregister Device: Use this option to register and deregister your device.

Device Options: Lets you set a passcode, enable Parental Controls, personalize your Kindle,
and select languages and dictionaries.

Device Passcode: Enables you to restrict access to your Kindle by setting a passcode.

You'll subsequently be prompted to enter the passcode whenever you turn on the device
or wake it from sleep. If you don't remember your passcode, you must contact Kindle
Customer Service.

Parental Controls: Choose between Kindle FreeTime and Restrictions. Use Kindle
FreeTime to create personalized profiles for your child, select books from your library to
share, and set daily reading goals while automatically blocking access to places you may
not want your child to go, such as the Kindle Store, Goodreads on Kindle, or the
Experimental Web Browser. Use Restrictions to manually block the Experimental Web
Browser, Kindle Store, Cloud, and/or Goodreads on Kindle. When you set up Kindle
FreeTime or turn on a restriction for the first time, you will be prompted to create a
password. Note that this password will be required to make changes to settings within
Parental Controls. To change the password, select Change Password from the Parental
Controls screen. If you forget your password, reset it by visiting
http://www.amazon.com/myk and deregistering your device, or by contacting Kindle
Customer Service. When Restrictions are enabled or a Kindle FreeTime profile is active,
you will see a lock icon at the top of the screen next to the Wi-Fi status indicator, and
the Deregistration and Reset Device options will be disabled.

Personalize your Kindle: Lets you manage your device name, add personal and contact
information, set device time, manage recommended content, change the next in series
option, manage Whispersync for Books, and view your Send-to-Kindle Email address.

Device Name: Lets you change the name displayed at the top of the Home screen.

Kindle User’s Guide 33
Chapter 5
Settings
Personal Info: Use this field to add personal or contact information, such as an
address or phone number, to help identify your Kindle in the event it is lost.

Device Time: Lets you set the current local time to be displayed on your Kindle. The
time displays at the top of the screen. To view the time from within a book, tap the
top of the screen.

Advanced Options: Lets you manage cover view recommendations, next in series
options, Whispersync for Books, and Special Offers.

Cover View Recommendations: When in cover view, this option allows
you to display or hide recommended content from the Kindle Store on
your Home screen.

Next in Series: Select to display an option to buy the next title in the series
when nearing the end of a book.

Whispersync for Books: Enable and disable the automatic backup of your
annotations, most recent page read, last page read, and collections to
Amazon’s servers.

Special Offers: Manage how Special Offers appear on your Kindle
Send-to-Kindle E-mail: Indicates the address to which documents should be
emailed so that they can be sent to your Kindle. Document formats supported by the
conversion service will be converted to Kindle format. (Charges may apply.) To
learn more about this feature, go to http://www.amazon.com/devicesupport.

Language and Dictionaries: Lets you select a language for your Kindle, add keyboards for
different languages, and select default dictionaries.

Language: Displays the current language for menus, alerts, and dialog boxes, and
lets you change to a different language.

Keyboards: Enables you to add keyboards for different languages. If you have
multiple keyboards, a Globe key is added to your keyboard. Simply tap to select
a different keyboard.

Dictionaries: Use to set the default dictionary for each language.

Reading Options: Lets you manage Word Wise, Vocabulary Builder, page refresh, social
networks, annotations, public notes, and popular highlights.

Language Learning: Enable Word Wise word hints in books and Vocabulary
Builder.

Word Wise: Display hints above challenging words in many popular
English-language titles. To turn off multiple hints for a word, disable the
Show Multiple-Choice Hints option.

Vocabulary Builder: Allows you to toggle on and off Vocabulary Builder.

Selecting off will remove Vocabulary Builder from the Home screen. Note
that words you look up are not added to Vocabulary Builder when it is off.

Page Refresh: Use to set your Kindle to refresh the display every time you turn the
page.

Social Networks: Allows you to link your Kindle to your social network accounts so
you can share highlights with your friends.

Kindle User’s Guide 34
Chapter 5
Settings
Notes & About This Book: Select to manage public notes, popular highlights, and
About This Book.

Popular Highlights: Toggle on and off the display of passages that are
most frequently highlighted by others.

Public Notes: Toggle on and off the display of notes and highlights made
by people you follow on https://kindle.amazon.com.

About This Book: Toggle on or off the display of information about the
book when you open it.

The Settings contextual menu
When you're on the Settings page, tapping the Menu button displays additional options:
Shop Kindle Store: Takes you to the Kindle Store.

Update Your Kindle: Installs the latest software for your Kindle. This option is disabled if
there are currently no software updates available on your Kindle.

Restart: Restarts your Kindle. You will not lose the books, clippings, or other files stored on
your Kindle. In the event your Kindle freezes up, press and hold the Power button for 7
seconds until the Power dialog displays and then select Restart. If the Power dialog does not
display, press and hold for 20 seconds.

Reset Device: Resets your Kindle to its original settings and restarts it. You should select this
action only if instructed to do so by Kindle Customer Service. Before you reset your Kindle to
its defaults, you must back up any personal documents that you'd like to keep. Once your
Kindle restarts, you will need to register and download your items from the Cloud. If you
want to passcode-protect your Kindle, you must also set up a passcode again.

Device Info: Displays your device's Wi-Fi MAC address, serial number, network capability,
firmware version, and free space available.

Legal: Provides trademark, copyright, and notices about the software installed on your
Kindle.

Sync and Check for Items: Tap to sync your Kindle with your online content.

Kindle User’s Guide 35
Chapter 6
Finding Additional Assistance
Chapter 6
Finding Additional Assistance
The Kindle Customer Service website at http://www.amazon.com/devicesupport has helpful
information, including frequently asked questions and how-to videos.

Kindle User’s Guide 36

## Appendix A

Product Information

## Appendix A

Product Information
Safety and Compliance Information
Use Responsibly. Read all instructions and safety information before use.

FAILURE TO FOLLOW THESE SAFETY INSTRUCTIONS COULD RESULT IN FIRE,
ELECTRIC SHOCK, OR OTHER INJURY OR DAMAGE.

Maintaining Your Kindle Device
Do not use your Kindle device or its accessories in rain, or near sinks or other wet locations.

Take care not to spill any food or liquid on your Kindle. If your device does get wet, unplug all
cables, turn off the wireless (tap the Menu button, select Settings, and enable Airplane Mode)
and let the screen revert to the screen saver. Wait for the device to dry completely before
pressing the power button to wake again. Do not attempt to dry your Kindle with an external
heat source, such as a microwave oven or hair dryer. Clean the screen with a soft cloth; be
careful not to wipe it with anything abrasive. When carrying your Kindle in a bag or briefcase,
keep a cover on to avoid scratches.

Don't expose your Kindle to extreme heat or cold. For example, don't leave it in the trunk of
your car in sub-zero or high-heat conditions.

Use of third party accessories may impact your Kindle's performance. In limited
circumstances, use of third party accessories may void your Kindle's limited warranty. Read
all safety instructions for any accessories before using them with your Kindle.

Servicing Your Device
If your device needs service, please contact Amazon Customer Support. Contact details can be
found at http://www.amazon.com/devicesupport.

Faulty service may void the warranty.

Battery Safety
The rechargeable battery in your Kindle should not be repaired or replaced except by
qualified personnel. For more information about batteries, go to
http://www.amazon.com/devicesupport. Your Kindle should only be charged using the USB
cable included with the device, or another USB cable approved for use with your Kindle, with
a compatible USB charger or USB port that meets the following requirements: USB-IF Battery
Charging Spec, Rev 1.2.

Kindle User’s Guide 37

## Appendix A

Product Information
Other Safety Considerations
 Engaging in repetitive motions such as pressing keys or playing some games may cause you
to experience occasional discomfort in your hands, arms, shoulders, neck, or other parts of
your body. Discontinue use of your device and consult a physician if you experience
headaches, blackouts, seizures, convulsion, eye or muscle twitching, loss of awareness,
involuntary movement, disorientation, or other discomfort. To reduce risk of these symptoms
avoid prolonged use, hold your device some distance from your eyes, use your device in a
well-lit room, and take frequent breaks.

 Small parts contained in your device and its accessories may present a choking hazard to
small children.

 Using your Kindle while operating a vehicle is not recommended and may be prohibited or
restricted in some areas. If you are in an area where using your Kindle while operating a
vehicle is allowed, always give full attention to the operation of the vehicle and stop using
your Kindle if it becomes a distraction.

 Personal medical devices, such as pacemakers, may be sensitive to magnetic and
electromagnetic fields. Since Kindle and certain Kindle accessories contain magnets and emit
electromagnetic fields, they should be kept at least 6 inches (approximately 15 cm) from any
personal medical device. If any interference is observed, consult with your physician before
resuming use. Items with magnetically-stored data, such as credit cards and hard drives, may
also be sensitive to magnetic or electromagnetic fields, and should not be placed near these
Kindle products.

Wireless Safety and Compliance
Turn your wireless connection off in areas where wireless use is forbidden or when it may
cause interference or danger. Some specific situations are described below. In general, you
should not use your Kindle with your wireless connection turned on any place you are not
allowed to use a cellular device.

Turn Off Wireless When Flying
To prevent possible interference with aircraft systems, the U.S. Federal Aviation
Administration regulations and many other aviation agencies require you to have permission
from a crewmember to use your device's wireless service.

Using Your Kindle Around Other Electronic Devices
Kindle generates, uses, and can radiate radio frequency (RF) energy and, if not used in
accordance with its instructions, may cause interference to radio communications and
electronic equipment. External RF signals may affect improperly installed or inadequately
shielded electronic operating systems, entertainment systems, and personal medical devices.

While most modern electronic equipment is shielded from external RF signals, if in doubt,
check with the manufacturer. For personal medical devices (such as pacemakers and hearing
aids), consult with your physician or the manufacturer to determine if they are adequately
shielded from external RF signals.

Kindle User’s Guide 38

## Appendix A

Product Information
Steps to Minimize Interference
If your Kindle does cause interference to radio or television reception (which you can
determine by turning your Kindle off and on), you can try to correct the interference by one
or more of the following measures: reorient or relocate the receiving antenna for the radio or
television; increase the separation between the radio or television and your Kindle; connect
equipment and receivers to different outlets; or consult the radio or television manufacturer
or an experienced radio/TV technician for help.

Watch for Signs
There are some places where RF signals could constitute a hazard, such as health care
facilities, and construction sites. If you are not sure, look around for signs indicating that two-
way radios or cell phones should be turned off.

In addition, turn off and do not charge your device if you are in any area with a potentially
explosive atmosphere, as sparks in such areas could cause an explosion or fire. Such areas are
usually, but not always, clearly identified, and include areas where you would normally be
advised to turn off your vehicle engine.

FCC Compliance Statement
This device and its related accessories like the adaptor (the "Products") comply with part 15
of the FCC Rules. Operation of each Product is subject to the following two conditions: (1)
each Product may not cause harmful interference, and (2) each Product must accept any
interference received, including interference that may cause undesired operation.

Note: The Products have been tested and found to comply with the limits for a Class B digital
device or external switching power supply, pursuant to part 15 of the FCC Rules. These limits
are designed to provide reasonable protection against harmful interference in a residential
installation. The Products generate, use and can radiate radio frequency energy and, if not
installed and used in accordance with the instructions, may cause harmful interference to
radio communications. However, there is no guarantee that interference will not occur in a
particular installation. If a Product does cause harmful interference to radio or television
reception, which can be determined by turning the Product off and on, the user is encouraged
to try to correct the interference by one or more of the following measures:
 Reorient or relocate the receiving antenna.

 Increase the separation between the equipment and receiver.

 Connect the equipment into an outlet on a circuit different from that to which the receiver is
connected.

 Consult the dealer or an experienced radio/TV technician for help.

Changes or modifications not expressly approved by the party responsible for compliance
could void the user's authority to operate the Product.

The device meets the FCC Radio Frequency Emission Guidelines and is certified with the FCC
as the FCC ID number found on the back of the device.

Kindle User’s Guide 39

## Appendix A

Product Information
Information Regarding Exposure to Radio Frequency Energy
Your Device is designed and manufactured not to exceed the emission limits for exposure to
RF energy set by the Federal Communications Commission of the United States (FCC).

Information on your Device is on file with the FCC and can be found by inputting your
Device’s FCC ID (which can be found on the back of your Device) into the FCC ID Search form
available at transition.fcc.gov/oet/ea/fccid.

Canadian Compliance Statement
This device complies with the Canadian ICES-003 Class B specifications. CAN ICES-3(B)/
NMB-3(B)
This device complies with RSS210 of Industry Canada. This Class B device meets all the
requirements of the Canadian interference-causing equipment regulations.

This device complies with Industry Canada license exempt RSS standard(s). Operation is
subject to the following two conditions:
1. this device may not cause interference, and
2. this device must accept any interference, including interference that may cause undesired
operation of the device.

This device is compliant with general population/uncontrolled RF exposure limits in IC RSS-
102.

Cet appareil numérique de la Classe B est conforme à la norme NMB-003 du Canada. CAN
ICES-3(B)/ NMB-3(B)
Cet appareil numérique de la Classe B respecte toutes les exigences du Règlement sur le
matériel brouilleur du Canada.

Cet appareil est conforme aux normes CNR exemptes de licence d'Industrie Canada. Le
fonctionnement est soumis aux deux conditions suivantes :
1. cet appareil ne doit pas provoquer d'interférences et
2. cet appareil doit accepter toute interférence, y compris celles susceptibles de provoquer un
fonctionnement non souhaité de l'appareil.

Cet appareil est conciliant avec les limites d'exposition de RF population/non contenu
générales dans IC RSS-102.

IEEE 1725 Battery Safety Statement
 Do not disassemble or open, crush, bend or deform, puncture or shred.

 Do not modify or remanufacture, attempt to insert foreign objects into the battery, immerse
or expose to water or other liquids, expose to fire, explosion or other hazard.

 Only use the battery with a charging system that has been qualified with the system per CTIA
Certification Requirements for Battery System Compliance to IEEE 1725. Use of an
unqualified battery or charger may present a risk of fire, explosion, leakage, or other hazard.

 Promptly dispose of used batteries in accordance with local regulations.

Kindle User’s Guide 40

## Appendix A

Product Information
 Avoid dropping the device or battery. If the device or battery is dropped, especially on a hard
surface, and the user suspects damage, do not attempt repair. Contact Amazon Customer
Service for assistance.

 The host device shall only be connected to CTIA certified adapters, products that bear the
USB-IF logo or products that have completed the USB-IF compliance program.

EU Conformity
Hereby, Amazon Fulfillment Services, Inc., declares that this device is in compliance with the
essential requirements and other relevant provisions of RTTE Directive 1999/5/EC. A copy of
the EU Declaration of Conformity is available at:
http://www.amazon.com/kindle_eu_complianceApplicable CE Marking:
CE SAR Compliance
This device meets the EU requirements (1999/519/EC) on the limitation of exposure of the
general public to electromagnetic fields by way of health protection.

The limits are part of extensive recommendations for the protection of the general public.

These recommendations have been developed and checked by independent scientific
organizations through regular and thorough evaluations of scientific studies. The unit of
measurement for the European Council's recommended limit for mobile devices is the
"Specific Absorption Rate" (SAR), and the SAR limit is 2.0 W/ kg averaged over 10 gram of
tissue. It meets the requirements of the International Commission on Non-Ionizing Radiation
Protection (ICNIRP).

Recycling Kindle Properly
In some areas, the disposal of certain electronic devices is regulated. Make sure you
dispose of or recycle Kindle in accordance with your local laws and regulations. For
information about recycling Kindle, go to http://www.amazon.com/devicesupport.

Product Specifications
Display — 6" diagonal XGA display, 758 x 1024 pixels, 212 dpi resolution, 16-level gray scale.

Size — 6.7 inches by 4.6 inches by 0.36 inches (169 mm by 117 mm by 9.16 mm);
Weight — Kindle Wi-Fi: 7.3 ounces (206 g); Kindle 3G+Wi-Fi: 7.6 ounces (215 g).

Storage — 2GB internal storage, with approximately 1GB available to the user.

Power — AC power adapter (sold separately) and rechargeable lithium polymer battery.

Connectivity — USB 2.0 (micro-B connector). 802.11b/g/n wireless modem in Kindle.

Operating temperature — 32°F to 95°F (0°C to 35°C).

Kindle User’s Guide 41

## Appendix A

Product Information
Storage temperature — 14°F to 113°F (-10°C to 45°C).

Wi-Fi — 802.11b/g/n.

LEGAL TERMS
Please read the applicable License Agreement and Terms of Use found at:
http://www.amazon.com/devicesupport
ONE-YEAR LIMITED WARRANTY
This Warranty for the Kindle Device (the "Device") is provided by the entity set forth in the
table below. The provider of this warranty is sometimes referred to herein as "we".

We warrant the Device against defects in materials and workmanship under ordinary
consumer use for one year from the date of original retail purchase. During this warranty
period, if a defect arises in the Device, and you follow the instructions for returning the
Device, we will, at our option, to the extent permitted by law, either (i) repair the Device using
either new or refurbished parts, (ii) replace the Device with a new or refurbished Device that
is equivalent to the Device to be replaced, or (iii) refund to you all or part of the purchase
price of the Device. This limited warranty applies, to the extent permitted by law, to any
repair, replacement part or replacement device for the remainder of the original warranty
period or for ninety days, whichever period is longer. All replaced parts and Devices for
which a refund is given shall become our property. This limited warranty applies only to
hardware components of the Device that are not subject to accident, misuse, neglect, fire or
other external causes, alterations, repair, or commercial use.

Instructions. For specific instructions about how to obtain warranty service for your Device,
please contact Customer Service using the contact information provided below. In general,
you will need to deliver your Device in either its original packaging or in equally protective
packaging to the address specified by Customer Service. Before you deliver your Device for
warranty service, it is your responsibility to back up any data, software, or other materials
you may have stored or preserved on your Device. It is possible that such data, software or
other materials will be lost or reformatted during service, and we will not be responsible for
any such damage or loss.

Limitations. TO THE EXTENT PERMITTED BY LAW, THE WARRANTY AND REMEDIES SET
FORTH ABOVE ARE EXCLUSIVE AND IN LIEU OF ALL OTHER WARRANTIES AND REMEDIES,
AND WE SPECIFICALLY DISCLAIM ALL STATUTORY OR IMPLIED WARRANTIES, INCLUDING,
BUT NOT LIMITED TO, WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND AGAINST HIDDEN OR LATENT DEFECTS. IF WE CANNOT LAWFULLY
DISCLAIM STATUTORY OR IMPLIED WARRANTIES, THEN TO THE EXTENT PERMITTED BY
LAW, ALL SUCH WARRANTIES SHALL BE LIMITED IN DURATION TO THE DURATION OF
THIS EXPRESS LIMITED WARRANTY AND TO REPAIR OR REPLACEMENT SERVICE.

SOME JURISDICTIONS DO NOT ALLOW LIMITATIONS ON HOW LONG A STATUTORY OR
IMPLIED WARRANTY LASTS, SO THE ABOVE LIMITATION MAY NOT APPLY TO YOU. WE ARE
NOT RESPONSIBLE FOR DIRECT, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES
RESULTING FROM ANY BREACH OF WARRANTY OR UNDER ANY OTHER LEGAL THEORY. IN
SOME JURISDICTIONS THE FOREGOING LIMITATION DOES NOT APPLY TO DEATH OR
Kindle User’s Guide 42

## Appendix A

Product Information
PERSONAL INJURY CLAIMS, OR ANY STATUTORY LIABILITY FOR INTENTIONAL AND GROSS
NEGLIGENT ACTS AND/OR OMISSIONS, SO THE ABOVE EXCLUSION OR LIMITATION MAY
NOT APPLY TO YOU. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OR
LIMITATION OF DIRECT, INCIDENTAL OR CONSEQUENTIAL DAMAGES, SO THE ABOVE
EXCLUSION OR LIMITATION MAY NOT APPLY TO YOU. THIS "LIMITATIONS" SECTION DOES
NOT APPLY TO CUSTOMERS IN THE EUROPEAN UNION.

This limited warranty gives you specific rights. You may have additional rights under
applicable law, and this limited warranty does not affect such rights.

FOR AUSTRALIAN CONSUMERS: Our goods come with guarantees that cannot be excluded
under the Australian Consumer Law. You are entitled to a replacement or refund for a major
failure and for compensation for any other reasonably foreseeable loss or damage. You are
also entitled to have the goods repaired or replaced if the goods fail to be of acceptable
quality and the failure does not amount to a major failure. Goods presented for repair may be
replaced by refurbished goods of the same type rather than being repaired. Refurbished parts
may be used to repair the goods.

Warranty Provider
If you purchased your Device: This Warranty is provided by:
From Amazon.co.uk, Amazon.de,
Amazon.fr, Amazon.it, Amazon.es, or
from authorised resellers located in
Europe
Amazon EU S.à r.l., 5 rue Plaetis, L-2338,
Luxembourg
From Amazon.ca
Amazon.com.ca, Inc., 410 Terry Ave.

North, Seattle, WA 98109-5210, United
States
From Amazon.in or authorised resellers
located in India
Amazon Seller Services Private Limited,
8th Floor, Brigade Gateway, 26/1 Dr.

Rajkumar Road, Bangalore, Karnataka-
560055, India
From Amazon.co.jp or from authorised
resellers located in Japan
Amazon.com Int’l Sales, Inc., 410 Terry
Ave. North, Seattle, WA 98109-5210,
United States
From Amazon.cn or from authorised
resellers located in the People’s
Republic of China
Amazon Joyo Co. Ltd., 26F, Bldg A, Ocean
International Center, No. 56 East 4th
Ring Road, Chaoyang District, Beijing,
China
From Amazon.com.br
Amazon Serviços de Varejo do Brasil
Ltda., Av. Presidente Juscelino
Kubitschek, 2041 - Torre E - 18º andar,
São Paulo - SP, 04543-000, Brazil
From any other Amazon website or Amazon Fulfillment Services, Inc., 410
Kindle User’s Guide 43

## Appendix A

Product Information
from authorized resellers located in
other countries
Terry Ave. North, Seattle, WA 98109-
5210, United States
Updates to this table may be posted on http://www.amazon.com/devicesupport.

Additional Information
You can find the Kindle Terms of Use, Kindle Store Terms of Use, One-Year Limited Warranty,
customer service contact information, and other applicable terms, limited warranty and
Kindle information at http://www.amazon.com/devicesupport.

Patent Notices
The Kindle device and/or methods used in association with the Kindle device may be covered
by one or more patents or pending patent applications.

Copyright, Trademark and Other Notices
Amazon Kindle device software, the Amazon Kindle Quick Start Guide, and the Amazon Kindle
User’s Guide © 2004-2014 Amazon.com, Inc. or its affiliates. All rights reserved.

1-CLICK, AMAZON, the AMAZON logo, KINDLE, KINDLE PAPERWHITE, KINDLE SINGLES,
KINDLE FREETIME, GOODREADS, WORD WISE, SPONSORED SCREENSAVERS, X-RAY,
MOBIPOCKET, WHISPERNET and WHISPERSYNC are trademarks of Amazon.com, Inc. or its
affiliates.

Java and all Java based trademarks and logos are trademarks or registered trademarks of Sun
Microsystems, Inc. in the U.S. and other countries.

XT9® Smart Input © 2008 Nuance Communications, Inc. XT9® and Nuance® are trademarks
or registered trademarks of Nuance Communications, Inc. and/or its licensors and are used
under license.

Contains iType™ from Monotype Imaging Inc. “Monotype” is a trademark of Monotype
Imaging Inc. registered in the U.S. Patent & Trademark Office and may be registered in certain
jurisdictions. Monotype® The Monotype Corporation.

All other brands, product names, company names, trademarks, and service marks are the
properties of their respective owners.

JI20141016-A